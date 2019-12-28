module Ruby2JS
  class Converter

    # (regexp
    #   (str "x")
    #   (regopt :i))

    handle :regexp do |*parts, opt|
      # remove "extended" from list of options
      extended = false
      opts = opt.children
      if opts.include? :x
        opts = opts - [:x]
        extended = true
      end

      # remove whitespace and comments from extended regular expressions
      if extended
        parts.map! do |part|
          if part.type == :str
            str = part.children.first 
            str = str.gsub(/ #.*/,'').gsub(/\s/,'')
            s(:str, str)
          else
            part
          end
        end
      end

      # in Ruby regular expressions, ^ and $ apply to each line
      if parts.first.type == :str and parts.first.children[0].start_with?('^')
        opts = opts + [:m] unless opts.include? :m or opts.include? 'm'
      elsif parts.last.type == :str and parts.last.children[0].end_with?('$')
        opts = opts + [:m] unless opts.include? :m or opts.include? 'm'
      end

      # in Ruby regular expressions, /A is the start of the string
      if parts.first.type == :str and parts.first.children[0].start_with?('\A')
        parts = [s(:str, parts.first.children[0].sub('\A', '^'))] +
          parts[1..-1]
      end

      # in Ruby regular expressions, /z is the end of the string
      if parts.last.type == :str and parts.last.children[0].end_with?('\z')
        parts = parts[0..-2] +
          [s(:str, parts.first.children[0].sub(/\\z\z/, '$'))]
      end

      # use slash syntax if there are few embedded slashes in the regexp
      if parts.all? {|part| part.type == :str}
        str = parts.map {|part| part.children.first}.join
        unless str.scan('/').length - str.scan("\\").length > 3
          return put "/#{ str.gsub('\\/', '/').gsub('/', '\\/') }/" +
            opts.join
        end
      end

      # create a new RegExp object
      put 'new RegExp('

      if parts.length == 1
        parse parts.first
      else
        parse s(:dstr, *parts)
      end

      unless opts.empty?
        put ", #{ opts.join.inspect}"
      end

      put ')'
    end
  end
end
