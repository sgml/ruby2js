require 'ruby2js'

module Ruby2JS
  module Filter
    module Underscore
      include SEXP

      def on_send(node)
        return super if node.children.first and node.children.first.children.last == :_

        method = node.children[1]
        return super if excluded?(method)

        if [:clone, :shuffle, :size, :compact, :flatten, :invert, :values,
          :uniq].include? method
          if node.is_method?  and node.children.length == 2
            process S(:send, s(:lvar, :_), method, node.children[0])
          else
            super
          end
        elsif method == :sample and  node.children.length <= 3
          process S(:send, s(:lvar, :_), :sample, node.children[0],
            *node.children[2..-1])
        elsif method == :has_key? and  node.children.length == 3
          process S(:send, s(:lvar, :_), :has, node.children[0],
            node.children[2])
        elsif method == :sort and  node.children.length == 2
          if node.is_method?
            process S(:send, s(:lvar, :_), :sortBy, node.children[0],
              s(:attr, s(:lvar, :_), :identity))
          else
            super
          end
        elsif method == :map
          if node.children.length == 3 and node.children[2].type == :block_pass
            process S(:send, s(:lvar, :_), :pluck, node.children[0],
              node.children[2].children.first)
          else
            super
          end
        elsif method == :merge and node.children.length >= 3
          process S(:send, s(:lvar, :_), :extend, s(:hash), node.children[0],
            *node.children[2..-1])
        elsif method == :merge! and node.children.length >= 3
          process S(:send, s(:lvar, :_), :extend, node.children[0],
            *node.children[2..-1])
        elsif method == :zip and node.children.length >= 3
          process S(:send, s(:lvar, :_), :zip, node.children[0],
            *node.children[2..-1])
        elsif method == :invoke
          if node.children.length >= 3 and node.children.last.type==:block_pass
            process S(:send, s(:lvar, :_), :invoke, node.children[0],
              node.children.last.children.first,
              *node.children[2..-2])
          else
            super
          end
        elsif [:where, :find_by].include? method
          method = (method == :where ? :where : :findWhere)
          process S(:send, s(:lvar, :_), method, node.children[0],
            *node.children[2..-1])
        elsif method == :reduce
          if node.children.length == 3 and node.children[2].type == :sym
            # input: a.reduce(:+)
            # output: _.reduce(_.rest(a), 
            #                  proc {|memo, item| return memo+item},
            #                  a[0])
            process S(:send, s(:lvar, :_), :reduce, 
              s(:send, s(:lvar, :_), :rest, node.children.first),
              s(:block, s(:send, nil, :proc), 
                s(:args, s(:arg, :memo), s(:arg, :item)),
                s(:autoreturn, s(:send, s(:lvar, :memo), 
                  node.children[2].children.first, s(:lvar, :item)))),
                s(:send, node.children.first, :[], s(:int, 0)))
          elsif node.children.last.type == :block_pass
            on_send node.updated(nil, [*node.children[0..1],
              node.children[2].children.first])
          elsif node.children.length == 4 and node.children[3].type == :sym
            # input: a.reduce(n, :+)
            # output: _.reduce(a, proc {|memo, item| return memo+item}, n)
            process S(:send, s(:lvar, :_), :reduce, node.children.first,
              s(:block, s(:send, nil, :proc), 
                s(:args, s(:arg, :memo), s(:arg, :item)),
                s(:autoreturn, s(:send, s(:lvar, :memo), 
                node.children[3].children.first, s(:lvar, :item)))),
                node.children[2])
          else
            super
          end

        elsif [:compact!, :flatten!, :shuffle!, :uniq!].
          include? method and node.is_method?
          # input: a.compact!
          # output: a.splice(0, a.length, *a.compact)
          target = node.children.first
          process S(:send, target, :splice, s(:int, 0), 
            s(:attr, target, :length), s(:splat, s(:send, target, 
            :"#{method.to_s[0..-2]}", *node.children[2..-1])))
        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        method = call.children[1]
        return super if excluded?(method)

        if [:sort_by, :group_by, :index_by, :count_by].include? method
          # input: a.sort_by {}
          # output: _.sortBy {return expression}
          method = method.to_s.sub(/\_by$/,'By').to_sym
          process S(:block, s(:send, s(:lvar, :_), method,
            call.children.first), node.children[1], 
            s(:autoreturn, node.children[2]))
        elsif [:find, :reject].include? method
          if call.children.length == 2
            # input: a.find {|item| item > 0}
            # output: _.find(a) {|item| return item > 0}
            process S(:block, s(:send, s(:lvar, :_), method, 
              call.children.first), node.children[1], 
              s(:autoreturn, node.children[2]))
          else
            super
          end

        elsif method == :times and call.children.length == 2
          # input: 5.times {|i| console.log i}
          # output: _.find(5) {|i| console.log(i)}
          process S(:block, s(:send, s(:lvar, :_), method, 
            call.children.first), node.children[1], node.children[2])

        elsif method == :reduce
          if call.children.length == 2
            # input: a.reduce {|memo, item| memo+item}
            # output: _.reduce(_.rest(a), 
            #                  proc {|memo, item| return memo+item},
            #                  a[0])
            process S(:call, s(:lvar, :_), :reduce, 
              s(:send, s(:lvar, :_), :rest, call.children.first),
              s(:block, s(:send, nil, :proc), 
                node.children[1], s(:autoreturn, node.children[2])),
                s(:send, call.children.first, :[], s(:int, 0)))
          elsif call.children.length == 3
            # input: a.reduce(n) {|memo, item| memo+item}
            # output: _.reduce(a, proc {|memo, item| return memo+item}, n)
            process S(:call, s(:lvar, :_), :reduce, call.children.first,
              s(:block, s(:send, nil, :proc), 
                node.children[1], s(:autoreturn, node.children[2])),
                call.children[2])
          end

        elsif [:map!, :reject!, :select!, :sort_by!].include? method
          # input: a.map! {expression}
          # output: a.splice(0, a.length, *a.map {expression})
          method = :"#{method.to_s[0..-2]}"
          target = call.children.first
          process S(:call, target, :splice, s(:splat, s(:send, s(:array, 
            s(:int, 0), s(:attr, target, :length)), :concat,
            s(:block, s(:send, target, method, *call.children[2..-1]),
            *node.children[1..-1]))))

        else
          super
        end
      end

      def on_erange(node)
        process s(:send, s(:lvar, :_), :range, *node.children)
      end

      def on_irange(node)
        if node.children.last.type == :int
          process S(:call, s(:lvar, :_), :range, node.children.first,
            s(:int, node.children.last.children.last+1))
        else
          process S(:call, s(:lvar, :_), :range, node.children.first,
            s(:send, node.children.last, :+, s(:int, 1)))
        end
      end

      def on_for(node)
        # pass through irange, erange unprocessed
        return super unless [:irange, :erange].include? node.children[1].type
        s(:for, process(node.children[0]), s(node.children[1].type,
          *process_all(node.children[1].children)), process(node.children[2]))
      end
    end

    DEFAULTS.push Underscore
  end
end
