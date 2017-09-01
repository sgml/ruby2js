require 'ruby2js'

module Ruby2JS
  module Filter
    module Vue
      include SEXP

      def initialize(*args)
        @vue_h = nil
        @vue_self = nil
        @vue_apply = nil
        @vue_inventory = Hash.new {|h, k| h[k] = []}
        super
      end

      def options=(options)
        super
        @vue_h ||= options[:vue_h]
      end

      # Example conversion
      #  before:
      #    (class (const nil :Foo) (const nil :Vue) nil)
      #  after:
      #    (casgn nil :Foo, (send nil, :Vue, :component, (:str, "foo"), 
      #      s(:hash)))
      def on_class(node)
        cname, inheritance, *body = node.children
        return super unless cname.children.first == nil
        return super unless inheritance == s(:const, nil, :Vue)

        # traverse down to actual list of class statements
        if body.length == 1
          if not body.first
            body = []
          elsif body.first.type == :begin
            body = body.first.children
          end
        end

        hash = []
        methods = []

        # insert constructor if none present
        unless body.any? {|statement| 
          statement.type == :def and statement.children.first ==:initialize}
        then
          body = body.dup
          body.unshift s(:def, :initialize, s(:args), nil)
        end

        @vue_inventory = vue_walk(node)

        # convert body into hash
        body.each do |statement|

          # named values
          if statement.type == :send and statement.children.first == nil
            if [:template, :props].include? statement.children[1]
              hash << s(:pair, s(:sym, statement.children[1]), 
                statement.children[2])
            end

          # methods
          elsif statement.type == :def
            begin
              @vue_self = s(:attr, s(:self), :$data)
              method, args, block = statement.children
              if method == :render
                args = s(:args, s(:arg, :$h)) if args.children.empty?

                block = s(:begin, block) unless block and block.type == :begin

                if
                  block.children.length != 1 or not block.children.last or
                  not [:send, :block].include? block.children.first.type
                then
                  # wrap multi-line blocks with a 'span' element
                  block = s(:return,
                    s(:block, s(:send, nil, :_span), s(:args), *block))
                end

                @vue_h = args.children.first.children.last
              elsif method == :initialize
                method = :data

                # find block
                if block == nil
                  block = s(:begin)
                elsif block.type != :begin
                  block = s(:begin, block)
                end

                simple = block.children.all? {|child| child.type == :ivasgn}

                # not so simple if ivars are being read as well as written
                if simple
                  block_inventory = vue_walk(block)
                  simple = block_inventory[:ivar].empty?
                end

                uninitialized = @vue_inventory[:ivar].dup

                block.children.each do |child|
                  if child.type == :ivasgn 
                    uninitialized.delete child.children.first
                  end
                end

                # convert to a hash
                if simple
                  # simple case: all statements are ivar assignments
                  pairs = block.children.map do |child|
                    s(:pair, s(:sym, child.children[0].to_s[1..-1]),
                     process(child.children[1]))
                  end

                  pairs += uninitialized.map do |symbol|
                    s(:pair, s(:sym, symbol.to_s[1..-1]), 
                      s(:attr, nil, :undefined))
                  end

                  block = s(:return, s(:hash, *pairs))
                else
                  # general case: build up a hash incrementally
                  block = s(:begin, s(:gvasgn, :$_, 
                    s(:hash, *uninitialized.map {|sym| 
                      s(:pair, s(:sym, sym.to_s[1..-1]),
                      s(:attr, nil, :undefined))})),
                    block, s(:return, s(:gvar, :$_)))
                  @vue_self = s(:gvar, :$_)
                end
              end

              # add to hash in the appropriate location
              pair = s(:pair, s(:sym, method),
                s(:block, s(:send, nil, :lambda), args, process(block)))
              if %w(data render beforeCreate created beforeMount mounted
                    beforeUpdate updated beforeDestroy destroyed
                ).include? method.to_s
              then
                hash << pair
              else
                methods << pair
              end
            ensure
              @vue_h = nil
              @vue_self = nil
            end
          end
        end

        unless hash.any? {|pair| pair.children[0].children[0] == :props}
          unless @vue_inventory[:cvar].empty?
            hash.unshift s(:pair, s(:sym, :props), s(:array, 
              *@vue_inventory[:cvar].map {|sym| s(:str, sym.to_s[2..-1])}))
          end
        end

        # add methods to hash
        unless methods.empty?
          hash << s(:pair, s(:sym, :methods), s(:hash, *methods))
        end

        # convert class name to camel case
        camel = cname.children.last.to_s.gsub(/[^\w]/, '-').
          sub(/^[A-Z]/) {|c| c.downcase}.
          gsub(/[A-Z]/) {|c| "-#{c.downcase}"}

        # build component
        s(:casgn, nil, cname.children.last,
          s(:send, s(:const, nil, :Vue), :component, 
          s(:str, camel), s(:hash, *hash)))
      end

      # expand 'wunderbar' like method calls
      def on_send(node)
        if not @vue_h
          # enable React filtering within React class method calls or
          # React component calls
          if
            node.children.first == s(:const, nil, :Vue)
          then
            begin
              vue_h, @vue_h = @vue_h, :$h
              return on_send(node)
            ensure
              @vue_h = vue_h
            end
          end
        end

        # map method calls involving i/g/c vars to straight calls
        #
        # input:
        #   @x.(a,b,c)
        # output:
        #   @x(a,b,c)
        if @vue_self and node.children[1] == :call
          if [:ivar, :gvar, :cvar].include? node.children.first.type
            return process(s(:send, node.children.first, nil,
              *node.children[2..-1]))
          else
            return super
          end
        end

        return super unless @vue_h

        if node.children[0] == nil and node.children[1] =~ /^_\w/
          tag = node.children[1].to_s[1..-1]
          hash = Hash.new {|h, k| h[k] = {}}
          args = []
          complex_block = []
          component = (tag =~ /^[A-Z]/)

          node.children[2..-1].each do |attr|
            if attr.type == :hash
              # attributes
              # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
              pairs = attr.children.dup

              # extract all class names
              classes = pairs.find_all do |pair|
                key = pair.children.first.children.first
                [:class, 'class', :className, 'className'].include? key
              end

              # combine all classes into a single value (or expression)
              if classes.length > 0
                expr = nil
                values = classes.map do |pair|
                  if [:sym, :str].include? pair.children.last.type
                    pair.children.last.children.first.to_s
                  else
                    expr = pair.children.last
                    ''
                  end
                end
                pairs -= classes
                if expr
                  if values.length > 1
                    while expr.type == :begin and expr.children.length == 1
                      expr = expr.children.first
                    end

                    if expr.type == :array
                      hash[:class] = s(:array, *expr.children,
                        *values.join(' ').split(' ').map {|str| s(:str, str)})
                    elsif expr.type == :hash
                      hash[:class] = s(:hash, *expr.children,
                        *values.join(' ').split(' ').
                          map {|str| s(:pair, s(:str, str), s(:true))})
                    else
                      if
                        expr.type == :if and expr.children[1] and
                        expr.children[1].type == :str
                      then
                        left = expr.children[1]
                        right = expr.children[2] || s(:str, '')

                        unless right.type == :str
                          right = s(:or, right, s(:str, '')) 
                        end

                        expr = expr.updated(nil, 
                          [expr.children[0], left, right])
                      elsif expr.type != :str
                        expr = s(:or, expr, s(:str, ''))
                      end

                      value = s(:send, s(:str, values.join(' ')), :+, expr)
                      pairs.unshift s(:pair, s(:sym, :class), value)
                    end
                  elsif [:hash, :array].include? expr.type
                    hash[:class] = expr
                  else
                    pairs.unshift s(:pair, s(:sym, :class), expr)
                  end
                else
                  hash[:class] = s(:array, 
                    *values.join(' ').split(' ').map {|str| s(:str, str)})
                end
              end

              # search for the presence of a 'style' attribute
              style = pairs.find_index do |pair|
                ['style', :style].include? pair.children.first.children.first
              end

              # converts style strings into style hashes
              if style and pairs[style].children[1].type == :str
                rules = []
                value = pairs[style].children[1].children[0]
                value.split(/;\s+/).each do |prop|
                  prop.strip!
                  next unless prop =~ /^([-a-z]+):\s*(.*)$/
                  name, value = $1, $2
                  name.gsub!(/-[a-z]/) {|str| str[1].upcase}
                  if value =~ /^-?\d+$/
                    rules << s(:pair, s(:str, name), s(:int, value.to_i))
                  elsif value =~ /^-?\d+$\.\d*/
                    rules << s(:pair, s(:str, name), s(:float, value.to_f))
                  else
                    rules << s(:pair, s(:str, name), s(:str, value))
                  end
                end
                pairs.delete_at(style)
                hash[:style] =  s(:hash, *rules)
              end

              # process remaining attributes
              pairs.each do |pair|
                name = pair.children[0].children[0].to_s
                if name =~ /^(nativeOn|on)([A-Z])(.*)/
                  hash[$1]["#{$2.downcase}#$3"] = pair.children[1]
                elsif component
                  hash[:props][name] = pair.children[1]
                elsif name =~ /^domProps([A-Z])(.*)/
                  hash[:domProps]["#{$1.downcase}#$2"] = pair.children[1]
                elsif name == 'style' and pair.children[1].type == :hash
                  hash[:style] = pair.children[1]
                elsif %w(key ref refInFor slot).include? name
                  hash[name] = pair.children[1]
                else
                  hash[:attrs][name] = pair.children[1]
                end
              end

            elsif attr.type == :block
              # traverse down to actual list of nested statements
              statements = attr.children[2..-1]
              if statements.length == 1
                if not statements.first
                  statements = []
                elsif statements.first.type == :begin
                  statements = statements.first.children
                end
              end

              # check for normal case: only elements and text
              simple = statements.all? do |arg|
                # explicit call to Vue.createElement
                next true if arg.children[1] == :createElement and
                  arg.children[0] == s(:const, nil, :Vue)

                # wunderbar style call
                arg = arg.children.first if arg.type == :block
                while arg.type == :send and arg.children.first != nil
                  arg = arg.children.first
                end
                arg.type == :send and arg.children[1] =~ /^_/
              end

              if simple
                args << s(:array, *statements)
              else
                complex_block += statements
              end

            else
              # text or child elements
              args << node.children[2]
            end
          end

          # support controlled form components
          if %w(input select textarea).include? tag
            # search for the presence of a 'value' attribute
            value = hash[:attrs]['value']

            # search for the presence of a 'onChange' attribute
            onChange = hash['on']['change']

            if value and value.type == :ivar and !onChange
              hash['domProps']['value'] ||= value
              hash['on']['input'] ||=
                s(:block, s(:send, nil, :proc), s(:args, s(:arg, :event)),
                s(:ivasgn, value.children.first,
                s(:attr, s(:attr, s(:lvar, :event), :target), :value)))
              hash[:attrs].delete('value')
            end

            if not value and not onChange and tag == 'input'
              # search for the presence of a 'checked' attribute
              checked = hash[:attrs]['checked']

              if checked and checked.type == :ivar
                hash['domProps']['checked'] ||= checked
                hash['on']['input'] ||=
                  s(:block, s(:send, nil, :proc), s(:args),
                  s(:ivasgn,checked.children.first,
                  s(:send, checked, :!)))
              end
            end
          end

          # put attributes up front
          unless hash.empty?
            pairs = hash.to_a.map do |k1, v1| 
              next if Hash === v1 and v1.empty?
              s(:pair, s(:str, k1.to_s), 
                if Parser::AST::Node === v1
                  v1
                else
                  s(:hash, *v1.map {|k2, v2| s(:pair, s(:str, k2.to_s), v2)})
                end
              )
            end
            args.unshift s(:hash, *pairs.compact)
          end

          # prepend element name
          if component
            args.unshift s(:const, nil, tag)
          else
            args.unshift s(:str, tag)
          end

          if complex_block.empty?
            # emit $h (createElement) call
            element = node.updated :send, [nil, @vue_h, *process_all(args)]
          else
            # calls to $h (createElement) which contain a block
            #
            # collect array of child elements in a proc, and call that proc
            #
            #   $h('tag', hash, proc {
            #     var $_ = []
            #     $_.push($h(...))
            #     return $_
            #   }())
            #
            begin
              vue_apply, @vue_apply = @vue_apply, true
              
              element = node.updated :send, [nil, @vue_h, 
                *process_all(args),
                s(:send, s(:block, s(:send, nil, :proc),
                  s(:args, s(:shadowarg, :$_)), s(:begin,
                  s(:lvasgn, :$_, s(:array)),
                  *process_all(complex_block),
                  s(:return, s(:lvar, :$_)))), :[])]
            ensure
              @vue_apply = vue_apply
            end
          end

          if @vue_apply
            # if apply is set, emit code that pushes result
            s(:send, s(:gvar, :$_), :push, element)
          else
            element
          end

        elsif node.children[0] == nil and node.children[1] == :_
          # text nodes
          # https://stackoverflow.com/questions/42414627/create-text-node-with-custom-render-function-in-vue-js
          text = s(:send, s(:self), :_v, process(node.children[2]))
          if @vue_apply
            # if apply is set, emit code that pushes text
            s(:send, s(:gvar, :$_), :push, text)
          else
            # simple/normal case: simply return the text
            text
          end

        elsif node.children[0]==s(:send, nil, :_) and node.children[1]==:[]
          if @vue_apply
            # if apply is set, emit code that pushes results
            s(:send, s(:gvar, :$_), :push, *process_all(node.children[2..-1]))
          elsif node.children.length == 3
            process(node.children[2])
          else
            # simple/normal case: simply return the element
            s(:splat, s(:array, *process_all(node.children[2..-1])))
          end

        elsif
          node.children[1] == :createElement and
          node.children[0] == s(:const, nil, :Vue)
        then
          # explicit calls to Vue.createElement
          element = node.updated nil, [nil, :$h, 
            *process_all(node.children[2..-1])]

          if @vue_apply
            # if apply is set, emit code that pushes result
            s(:send, s(:gvar, :$_), :push, element)
          else
            element
          end

        elsif node.children[0] and node.children[0].type == :send
          # determine if markaby style class and id names are being used
          child = node
          test = child.children.first
          while test and test.type == :send and not test.is_method?
            child, test = test, test.children.first
          end

          if child.children[0] == nil and child.children[1] =~ /^_\w/
            # capture the arguments provided on the current node
            children = node.children[2..-1]

            # convert method calls to id and class values
            while node != child
              if node.children[1] !~ /!$/
                # convert method name to hash {class: name} pair
                pair = s(:pair, s(:sym, :class),
                  s(:str, node.children[1].to_s.gsub('_','-')))
              else
                # convert method name to hash {id: name} pair
                pair = s(:pair, s(:sym, :id),
                  s(:str, node.children[1].to_s[0..-2].gsub('_','-')))
              end

              # if a hash argument is already passed, merge in id value
              hash = children.find_index {|cnode| cnode.type == :hash}
              if hash
                children[hash] = s(:hash, pair, *children[hash].children)
              else
                children << s(:hash, pair)
              end

              # advance to next node
              node = node.children.first
            end

            # collapse series of method calls into a single call
            return process(node.updated(nil, [*node.children[0..1], *children]))

          else
            super
          end

        else
          super
        end
      end

      # convert blocks to proc arguments
      def on_block(node)
        child = node.children.first

        # map Vue.render(el, &block) to Vue.new(el: el, render: block)
        if
          child.children[1] == :render and
          child.children[0] == s(:const, nil, :Vue)
        then
          begin
            arg = node.children[1].children[0] || s(:arg, :$h)
            vue_h, @vue_h = @vue_h, arg.children.first

            block = node.children[2]
            block = s(:begin, block) unless block and block.type == :begin

            if
              block.children.length != 1 or not block.children.last or
              not [:send, :block].include? block.children.first.type
            then
              # wrap multi-line blocks with a 'span' element
              block = s(:return,
                s(:block, s(:send, nil, :_span), s(:args), *block))
            end

            return node.updated :send, [child.children[0], :new,
              s(:hash, s(:pair, s(:sym, :el), process(child.children[2])),
                s(:pair, s(:sym, :render), s(:block, s(:send, nil, :lambda),
                s(:args, s(:arg, @vue_h)), process(block))))]
          ensure
            @vue_h = vue_h
          end
        end

        return super unless @vue_h

        if
          child.children[1] == :createElement and
          child.children[0] == s(:const, nil, :Vue)
        then
          # block calls to Vue.createElement
          #
          # collect array of child elements in a proc, and call that proc
          #
          #   $h('tag', hash, proc {
          #     var $_ = []
          #     $_.push($h(...))
          #     return $_
          #   }())
          #
          begin
            vue_apply, @vue_apply = @vue_apply, true
            
            element = node.updated :send, [nil, @vue_h, 
              *child.children[2..-1],
              s(:send, s(:block, s(:send, nil, :proc),
                s(:args, s(:shadowarg, :$_)), s(:begin,
                s(:lvasgn, :$_, s(:array)), 
                process(node.children[2]),
                s(:return, s(:lvar, :$_)))), :[])]
          ensure
            @vue_apply = vue_apply
          end

          if @vue_apply
            # if apply is set, emit code that pushes result
            return s(:send, s(:gvar, :$_), :push, element)
          else
            return element
          end
        end

        # traverse through potential "css proxy" style method calls
        child = node.children.first
        test = child.children.first
        while test and test.type == :send and not test.is_method?
          child, test = test, test.children.first
        end

        # wunderbar style calls
        if child.children[0] == nil and child.children[1] =~ /^_\w/
          if node.children[1].children.empty?
            # append block as a standalone proc
            block = s(:block, s(:send, nil, :proc), s(:args),
              *node.children[2..-1])
            return on_send node.children.first.updated(:send,
              [*node.children.first.children, block])
          else
            # iterate over Enumerable arguments if there are args present
            send = node.children.first.children
            return super if send.length < 3
            return process s(:block, s(:send, *send[0..1], *send[3..-1]),
              s(:args), s(:block, s(:send, send[2], :forEach),
              *node.children[1..-1]))
          end
        else
          super
        end
      end

      # expand @@ to self
      def on_cvar(node)
        return super unless @vue_self
        s(:attr, s(:attr, s(:self), :$props), node.children[0].to_s[2..-1])
      end

      # prevent attempts to assign to Vue properties
      def on_cvasgn(node)
        return super unless @vue_self
        raise NotImplementedError, "setting a Vue property"
      end

      # expand @ to @vue_self
      def on_ivar(node)
        return super unless @vue_self
        s(:attr, @vue_self, node.children[0].to_s[1..-1])
      end

      # expand @= to @vue_self.=
      def on_ivasgn(node)
        return super unless @vue_self 
        if node.children.length == 1
          s(:attr, @vue_self, "#{node.children[0].to_s[1..-1]}")
        else
          s(:send, @vue_self, "#{node.children[0].to_s[1..-1]}=", 
            process(node.children[1]))
        end
      end

      def on_op_asgn(node)
        return super unless @vue_self
        return super unless node.children.first.type == :ivasgn
        node.updated nil, [s(:attr, @vue_self, 
          node.children[0].children[0].to_s[1..-1]),
          node.children[1], process(node.children[2])]
      end

      # gather ivar and cvar usage
      def vue_walk(node, inventory = Hash.new {|h, k| h[k] = []})
        # extract ivars and cvars
        if [:ivar, :cvar].include? node.type
          symbol = node.children.first
          unless inventory[node.type].include? symbol
            inventory[node.type] << symbol
          end
        elsif node.type == :ivasgn
          symbol = nil
          symbol = node.children.first if node.children.length == 1
          if node.children.length == 2
            value = node.children[-1]
            symbol = value.children.first if value.type == :ivasgn
          end

          if symbol
            unless inventory[:ivar].include? symbol
              inventory[:ivar] << symbol
            end
          end
        end

        # recurse
        node.children.each do |child|
          vue_walk(child, inventory) if Parser::AST::Node === child
        end

        return inventory
      end
    end

    DEFAULTS.push Vue
  end
end
