require 'net/http'

module ActiveXML
  module Transport

    class Error < StandardError; end
    class ConnectionError < Error; end
    class UnauthorizedError < Error; end
    class ForbiddenError < Error; end
    class NotFoundError < Error; end

    class Abstract
      class << self
        def register_protocol( proto )
          ActiveXML::Config.register_transport self, proto.to_s
        end

        # spawn is called from within ActiveXML::Config::TransportMap.connect to
        # generate the actual transport instance for a specific model. May be
        # overridden in derived classes to implement some sort of connection
        # cache or singleton transport objects. The default implementation is
        # to create an own instance for each model.
        def spawn( target_uri, opt={} )
          self.new opt
        end

        def logger
          ActiveXML::Base.config.logger
        end
      end

      attr_accessor :target_uri

      def initialize( target_uri, opt={} )
      end

      def find( *args )
      end

      def save
      end

      def login( user, password )
      end

      def logger
        ActiveXML::Base.config.logger
      end
    end

    #TODO: put lots of stuff into base class
    require 'base64'
    class Rest < Abstract
      register_protocol 'rest'
      
      class << self
        def spawn( target_uri, opt={} )
          @transport_obj ||= new( target_uri, opt )
        end
      end

      def initialize( target_uri, opt={} )
        @options = opt
        if @options.has_key? :all
          @options[:all].scheme = "http"
        end
        @http_header = {}
     end

      def target_uri=(uri)
        uri.scheme = "http"
        @target_uri = uri
      end

      def login( user, password )
        @http_header ||= Hash.new
        @http_header['Authorization'] = 'Basic ' + Base64.encode64( "#{user}:#{password}" )
      end
     
      # returns document payload as string
      def find( model, *args )
        params = Hash.new
        symbolified_model = model.name.downcase.to_sym
        uri = ActiveXML::Config::TransportMap.target_for( symbolified_model )
        options = ActiveXML::Config::TransportMap.options_for( symbolified_model )
        case args[0]
        when Symbol
          logger.debug "Transport.find: using symbol"
          raise "Illegal symbol, must be :all (or String/Hash)" unless args[0] == :all
          uri = options[:all]
          if args.length > 1
            params = args[1].merge params
          end
        when String
          logger.debug "Transport.find: using string"
          params[:name] = args[0]
          if args.length > 1
            params = args[1].merge params
          end
        when Hash
          logger.debug "Transport.find: using hash"
          params = args[0]
        else
          raise "Illegal first parameter, must be Symbol/String/Hash"
        end

        logger.debug "uri is: #{uri}"
        url = substitute_uri( uri, params )

        obj = model.new( http_do( 'get', url ) )
        obj.instance_variable_set( '@init_options', params )
        return obj
      end

      def save( object )
        logger.debug "saving #{object.inspect}"
        url = substituted_uri_for( object )
        http_do 'put', url, object.dump_xml
      end

      # defines an additional header that is passed to the REST server on every subsequent request
      # e.g.: set_additional_header( "X-Username", "margarethe" )
      def set_additional_header( key, value )
        if value.nil? and @http_header.has_key? key
          @http_header[key] = nil
        end

        @http_header[key] = value
      end

      # delete a header field set with set_additional_header
      def delete_additional_header( key )
        if @http_header.has_key? key
          @http_header.delete key
        end
      end

      def direct_http( url, opt={} )
        defaults = {:method => "GET"}
        opt = defaults.merge opt

        #set default host if not set in uri
        if not url.host
          host, port = ActiveXML::Config::TransportMap.get_default_server( "rest" )
          url.host = host
          url.port = port unless port.nil?
        end

        logger.debug "--> direct_http url: #{url.inspect}"

        http_do opt[:method], url, opt[:data]
      end

      #replaces the parameter parts in the uri from the config file with the correct values
      def substitute_uri( uri, params )
        u = uri.clone
        u.scheme = "http"
        u.path = URI.escape(uri.path.split(/\//).map { |x| x =~ /^:(\w+)/ ? params[$1.to_sym] : x }.join("/"))
        if uri.query
          u.query = URI.escape(uri.query.split(/=/).map { |x| x =~ /^:(\w+)/ ? params[$1.to_sym] : x }.join("="))
        end
        u.path.gsub!(/\/+/, '/')
        return u
      end
      private :substitute_uri

      def substituted_uri_for( object )
        symbolified_model = object.class.name.downcase.to_sym
        uri = ActiveXML::Config::TransportMap.target_for( symbolified_model )
        substitute_uri( uri, object.instance_variable_get("@init_options") )
      end
      private :substituted_uri_for

      def http_do( method, url, data=nil )
        logger.debug "http_do: url: #{url}"
        begin
          response = Net::HTTP.start(url.host, url.port) do |http|
            path = URI.escape(url.path)
            if url.query
              path += "?" + URI.escape(url.query)
            end
            logger.debug "http_do: path: #{path}"

            case method
            when /get/i
              http.get path, @http_header
            when /put/i
              raise "PUT without data" if data.nil?
              http.put path, data, @http_header
            when /post/i
              raise "POST without data" if data.nil?
              http.post path, data, @http_header
            when /delete/i
              http.delete path, @http_header
            else
              raise "unknown HTTP method: #{method.inspect}"
            end
          end
        rescue SystemCallError => err
          raise ConnectionError, "Failed to establish connection: "+err.message
        end
        handle_response( response )
      end
      private :http_do

      def handle_response( http_response )
        case http_response
        when Net::HTTPSuccess, Net::HTTPRedirection
          return http_response.read_body
        when Net::HTTPNotFound
          raise NotFoundError, http_response.read_body
        when Net::HTTPUnauthorized
          raise UnauthorizedError, http_response.read_body
        when Net::HTTPForbidden
          raise ForbiddenError, http_response.read_body
        when Net::HTTPClientError, Net::HTTPServerError
          raise Error, http_response.read_body
        end
        raise Error, http_response.read_body
      end
      private :handle_response
    
    end
  end
end
