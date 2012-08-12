require "erubis"
require "timeout"

module Row
  class Handler
    class NoSuchExt < StandardError; end
    class NoSuchApp < StandardError; end

    attr_reader :input

    def initialize(input)
      @input = input
    end
    
    def run
      parse_request
      spawn_app

      if @output
        pass_request
        pass_response
      end
    ensure
      @output.close if @output
    end

    def spawn_app
      @ext, @app_name = parse_host
      raise NoSuchExt.new unless Config.supported_ext?(@ext)

      if Config.configured_app?(@app_name)
        @output = Spawner.new(@app_name).socket
      elsif Config.configured_default_app?
        @app_name = :default
        @output = Spawner.new(:default).socket
      else
        raise NoSuchApp.new
      end
    rescue NoSuchExt => e
      Row.logger.debug("No such extension: #{@ext}")
      render(:no_such_ext)
    rescue NoSuchApp => e
      Row.logger.debug("No such application: #{@app_name}")
      render(:no_such_app)
#    rescue => exception
#      @exception = exception
#      render(:spawn_error)
    end

    def parse_request
      @request_headers = {}
      @request = []

      line = @input.gets
#      line.force_encoding("ASCII-8BIT") if line.respond_to?(:force_encoding)
      @request << line

      if line.strip =~ %r{^([A-Z]+) (.+) (HTTP/\d\.\d)$}
        @http_method  = $1
        @request_uri  = $2
        @http_version = $3
      end

      while line = input.gets
#        line.force_encoding("ASCII-8BIT") if line.respond_to?(:force_encoding)
        @request_headers[$1.downcase] = $2 if line.strip =~ /^([^:]+):\s*(.*)$/
        @request << line
        break if line.strip.empty?
      end
    end

    def pass_request
      @request.each { |line| @output.write(line) }
      content_length = @request_headers["content-length"].to_i
      @output.write(@input.read(content_length)) if content_length > 0
      @output.flush
    end

    def pass_response
      @response_headers = {}

      while line = @output.gets
#        line.force_encoding("ASCII-8BIT") if line.respond_to?(:force_encoding)
        @response_headers[$1.downcase] = $2 if line.strip =~ /^([^:]+):\s*(.*)$/
        @input.write(line)
        break if line.strip.empty?
      end

      content_length = @response_headers["content-length"].to_i
      if content_length > 0
        @input.write(@output.read(content_length)) 
      elsif @response_headers["connection"] == "close"
        begin
          @input.write(@output.read)
        rescue EOFError
        end
      end
      @input.flush
    end

    def parse_host
      ary = @request_headers["host"].split(".")
      [ ary.pop.split(":").first, ary.pop ]
    end

    def render(template, options = {})
      case options[:code] || 404
      when 404 then @input.write("HTTP/1.1 404 NOT FOUND\r\n")
      when 500 then @input.write("HTTP/1.1 500 SERVER ERROR\r\n")
      end
      @input.write("Content-Type: text/html\r\n")
      @input.write("Connection: close\r\n")
      @input.write("\r\n")

      tpl = Erubis::Eruby.new(File.read(template_path(template)))
      @input.write(tpl.evaluate(self))

      @input.flush
    end

    def template_path(template)
      File.join(ROOT, "templates", "#{template}.erb")
    end
  end
end
