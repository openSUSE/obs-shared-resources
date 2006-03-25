
require 'net/http'

module ActiveXML
  module Transport
    class Error < StandardError; end

    class ConnectionError < Error; end

    class Abstract
      class << self
        def register_protocol( proto )
          ActiveXML::Config.register_transport self, proto.to_s
        end
      end
      attr_accessor :target_uri

      def initialize( opt={} )
      end

      def find( *args )
      end

      def logger
        RAILS_DEFAULT_LOGGER
      end
    end

    
    #TODO: put lots of stuff into base class
    class Rest < Abstract
      register_protocol 'rest'

      def initialize( opt={} )
        @options = opt
        if @options.has_key? :all
          @options[:all].scheme = "http"
        end
      end

      def target_uri=(uri)
        uri.scheme = "http"
        @target_uri = uri
      end
     
      # returns document payload as string
      def find( *args )
        params = Hash.new
        uri = @target_uri
        case args[0]
        when Symbol
          raise "Illegal symbol, must be :all (or String/Hash)" unless args[0] == :all
          uri = @options[:all]
          if args.length > 1
            params = args[1].merge params
          end
        when String
          params[:name] = args[0]
          if args.length > 1
            params = args[1].merge params
          end
        when Hash
          params = args[0]
        else
          raise "Illegal first parameter, must be Symbol/String/Hash"
        end

        logger.debug "uri is: #{uri}"
        url = substitute_uri( uri, params )

        do_get( url )
      end

      def substitute_uri( uri, params )
        u = uri.clone
        u.path = uri.path.split(/\//).map { |x| x =~ /^:/ ? params[x[1,x.length].to_sym] : x }.join("/")
        return u
      end
      private :substitute_uri

      def do_get( url )
        logger.debug "url: #{url}"
        require 'base64'
        http_header = {
          'Authorization' => 'Basic ' + Base64.encode64( "abauer:asdfasdf" )
        }
        begin
          response = Net::HTTP.start(url.host, url.port) do |http|
            http.get url.path, http_header
          end

          handle_response( response )
        rescue SystemCallError => err
          raise ConnectionError, "Failed to establish connection: "+err.message
        end
      end
      private :do_get

      def handle_response( http_response )
        http_response.body
      end
      private :handle_response
    end
  end
end
