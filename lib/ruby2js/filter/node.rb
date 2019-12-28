require 'ruby2js'
require 'set'

module Ruby2JS
  module Filter
    module Node
      include SEXP
      extend SEXP

      NODE_SETUP = {
        child_process: s(:casgn, nil, :child_process, 
          s(:send, nil, :require, s(:str, "child_process"))),
        fs: s(:casgn, nil, :fs, s(:send, nil, :require, s(:str, "fs"))),
        ARGV: s(:lvasgn, :ARGV, s(:send, s(:attr, 
          s(:attr, nil, :process), :argv), :slice, s(:int, 2)))
      }

      def initialize(*args)
        @node_setup = nil
        super
      end

      def process(node)
        return super if @node_setup
        @node_setup = Set.new
        result = super

        if @node_setup.empty?
          result
        else
          s(:begin, *@node_setup.to_a.map {|token| NODE_SETUP[token]},
            result)
        end
      end

      def on_send(node)
        target, method, *args = node.children

        if target == nil
          if method == :__dir__ and args.length == 0
            S(:attr, nil, :__dirname)

          elsif method == :exit and args.length <= 1
            s(:send, s(:attr, nil, :process), :exit, *process_all(args));

          elsif method == :system
            @node_setup << :child_process

            if args.length == 1
              s(:send, s(:attr, nil, :child_process), :execSync,
              process(args.first),
              s(:hash, s(:pair, s(:sym, :stdio), s(:str, 'inherit'))))
            else
              s(:send, s(:attr, nil, :child_process), :execFileSync,
              process(args.first), s(:array, *process_all(args[1..-1])),
              s(:hash, s(:pair, s(:sym, :stdio), s(:str, 'inherit'))))
            end

          elsif 
            method == :require and args.length == 1 and 
            args.first.type == :str and 
            %w(fileutils tmpdir).include? args.first.children.first
          then
            s(:begin)

          else
            super
          end

        elsif 
          [:File, :IO].include? target.children.last and
          target.type == :const and target.children.first == nil
        then
          if method == :read and args.length == 1
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :readFileSync, *process_all(args),
              s(:str, 'utf8'))

          elsif method == :write and args.length == 2
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :writeFileSync, *process_all(args))

          elsif target.children.last == :IO
            super

          elsif [:exist?, :exists?].include? method and args.length == 1
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :existsSync, process(args.first))

          elsif method == :readlink and args.length == 1
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :readlinkSync, process(args.first))

          elsif method == :realpath and args.length == 1
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :realpathSync, process(args.first))

          elsif method == :rename and args.length == 2
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :renameSync, *process_all(args))

          elsif 
            [:chmod, :lchmod].include? method and 
            args.length > 1 and args.first.type == :int
          then
            @node_setup << :fs

            S(:begin, *args[1..-1].map{|file|
              S(:send, s(:attr, nil, :fs), method.to_s + 'Sync', process(file),
                s(:octal, *args.first.children))
            })

          elsif 
            [:chown, :lchown].include? method and args.length > 2 and 
            args[0].type == :int and args[1].type == :int
          then
            @node_setup << :fs

            S(:begin, *args[2..-1].map{|file|
              s(:send, s(:attr, nil, :fs), method.to_s + 'Sync', process(file),
                *process_all(args[0..1]))
            })

          elsif [:ln, :link].include? method and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :linkSync, *process_all(args))
            
          elsif method == :symlink and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :symlinkSync, *process_all(args))
            
          elsif method == :truncate and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :truncateSync, *process_all(args))
            
          elsif [:stat, :lstat].include? method and args.length == 1
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), method.to_s + 'Sync',
              process(args.first))

          elsif method == :unlink and args.length == 1
            @node_setup << :fs
            S(:begin, *args.map{|file|
              S(:send, s(:attr, nil, :fs), :unlinkSync, process(file))
            })

          else
            super
          end

        elsif 
          target.children.last == :FileUtils and
          target.type == :const and target.children.first == nil
        then

          list = proc do |arg|
            if arg.type == :array
              arg.children
            else
              [arg]
            end
          end
            
          if [:cp, :copy].include? method and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :copyFileSync, *process_all(args))
            
          elsif [:mv, :move].include? method and args.length == 2
            @node_setup << :fs
            S(:send, s(:attr, nil, :fs), :renameSync, *process_all(args))

          elsif method == :mkdir and args.length == 1
            @node_setup << :fs
            S(:begin, *list[args.last].map {|file|
              s(:send, s(:attr, nil, :fs), :mkdirSync, process(file))
            })
            
          elsif method == :cd and args.length == 1
            S(:send, s(:attr, nil, :process), :chdir, *process_all(args))

          elsif method == :pwd and args.length == 0
            s(:send, s(:attr, nil, :process), :cwd)

          elsif method == :rmdir and args.length == 1
            @node_setup << :fs
            S(:begin, *list[args.last].map {|file|
              s(:send, s(:attr, nil, :fs), :rmdirSync, process(file))
            })

          elsif method == :ln and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :linkSync, *process_all(args))
            
          elsif method == :ln_s and args.length == 2
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :symlinkSync, *process_all(args))
            
          elsif method == :rm and args.length == 1
            @node_setup << :fs
            S(:begin, *list[args.last].map {|file|
              s(:send, s(:attr, nil, :fs), :unlinkSync, process(file))
            })

          elsif 
            method == :chmod and args.length == 2 and args.first.type == :int
          then
            @node_setup << :fs

            S(:begin, *list[args.last].map {|file|
              S(:send, s(:attr, nil, :fs), method.to_s + 'Sync', process(file),
                s(:octal, *args.first.children))
            })

          elsif 
            method == :chown and args.length == 3 and 
            args[0].type == :int and args[1].type == :int
          then
            @node_setup << :fs

            S(:begin, *list[args.last].map {|file|
              s(:send, s(:attr, nil, :fs), method.to_s + 'Sync', process(file),
                *process_all(args[0..1]))})

          elsif method == :touch
            @node_setup << :fs

            S(:begin, *list[args.first].map {|file|
              S(:send, s(:attr, nil, :fs), :closeSync,
                s(:send, s(:attr, nil, :fs), :openSync, file,
                s(:str, "w")))})

          else
            super
          end

        elsif 
          target.type == :const and target.children.first == nil and
          target.children.last == :Dir
        then
          if method == :chdir and args.length == 1
            S(:send, s(:attr, nil, :process), :chdir, *process_all(args))
          elsif method == :pwd and args.length == 0
            s(:send, s(:attr, nil, :process), :cwd)
          elsif method == :entries
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :readdirSync, *process_all(args))
          elsif method == :mkdir and args.length == 1
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :mkdirSync, process(args.first))
          elsif method == :rmdir and args.length == 1
            @node_setup << :fs
            s(:send, s(:attr, nil, :fs), :rmdirSync, process(args.first))
          elsif method == :mktmpdir and args.length <=1
            @node_setup << :fs
            if args.length == 0
              prefix = s(:str, 'd')
            elsif args.first.type == :array
              prefix = args.first.children.first
            else
              prefix = args.first
            end

            s(:send, s(:attr, nil, :fs), :mkdtempSync, process(prefix))
          else
            super
          end

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        target, method, *args = call.children

        if 
          method == :chdir and args.length == 1 and
          target.children.last == :Dir and
          target.type == :const and target.children.first == nil
        then
          s(:begin,
            s(:gvasgn, :$oldwd, s(:send, s(:attr, nil, :process), :cwd)),
            s(:kwbegin, s(:ensure, 
              s(:begin, process(call), process(node.children.last)),
              s(:send, s(:attr, nil, :process), :chdir, s(:gvar, :$oldwd)))))
        else
          super
        end
      end

      def on_const(node)
        if node.children == [nil, :ARGV]
          @node_setup << :ARGV
          super
        elsif node.children == [nil, :ENV]
          S(:attr, s(:attr, nil, :process), :env)
        elsif node.children == [nil, :STDIN]
          S(:attr, s(:attr, nil, :process), :stdin)
        elsif node.children == [nil, :STDOUT]
          S(:attr, s(:attr, nil, :process), :stdout)
        elsif node.children == [nil, :STDERR]
          S(:attr, s(:attr, nil, :process), :stderr)
        else
          super
        end
      end

      def on_gvar(node)
        if node.children == [:$stdin]
          S(:attr, s(:attr, nil, :process), :stdin)
        elsif node.children == [:$stdout]
          S(:attr, s(:attr, nil, :process), :stdout)
        elsif node.children == [:$stderr]
          S(:attr, s(:attr, nil, :process), :stderr)
        else
          super
        end
      end

      def on_xstr(node)
        @node_setup << :child_process

        children = node.children.dup
        command = children.shift
        while children.length > 0
          command = s(:send, accumulator, :+, children.shift)
        end

        s(:send, s(:attr, nil, :child_process), :execSync, command,
          s(:hash, s(:pair, s(:sym, :encoding), s(:str, 'utf8'))))
      end

      def on___FILE__(node)
        s(:attr, nil, :__filename)
      end
    end

    DEFAULTS.push Node
  end
end
