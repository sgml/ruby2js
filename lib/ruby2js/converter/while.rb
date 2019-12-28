module Ruby2JS
  class Converter

    # (while
    #   (true)
    #   (...))

    handle :while do |condition, block|
      begin
        next_token, @next_token = @next_token, :continue

        # handle while loops that assign a variable
        while condition.type == :begin and condition.children.length == 1
          condition = condition.children.first
        end

        if condition.type == :lvasgn
          var = condition.children[0]
          unless @vars[var]
            put "#{es2015 ? 'let' : 'var'} #{var}#@sep" 
            @vars[var] = true
          end
        end

        put 'while ('; parse condition; puts ') {'; scope block; sput '}'
      ensure
        @next_token = next_token
      end
    end
  end
end
