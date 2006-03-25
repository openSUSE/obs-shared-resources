require 'uri'

module ActiveXML
  module Config

    DEFAULTS = Hash.new
    DEFAULTS[:xml_backend] = "rexml"
    DEFAULTS[:transport_plugins] = "rest"

    def self.append_features(base)
      super
      base.extend ClassMethods
    end
    
    module ClassMethods
      # defines ActiveXML::Base.config. Returns the ActiveXML::Config module from which you
      # can get/set the current configuration by using the dynamically added accessors. 
      # ActiveXML::Base.config can also be called with a block which gets passed the Config object.
      # The block style call is typically used from the environment files in ${RAILS_ROOT}/config
      # 
      # Example:
      # ActiveXML::Base.config do |conf|
      #   conf.xml_backend = "rexml"
      # end
      #
      # Configuration options can also be accessed by calling the accessor methods directly on
      # ActiveXML::Config :
      #
      # Example:
      # ActiveXML::Config.xml_backend = "xml_smart"
      # 
      def config
        yield(ActiveXML::Config) if block_given?
        return ActiveXML::Config
      end
    end
    
    class TransportMap
      class << self
        def logger
          RAILS_DEFAULT_LOGGER
        end
        
        def default_server( transport, location )
          @default_servers ||= Hash.new
          logger.debug "default_server for #{transport.inspect} models: #{location}"
          @default_servers[transport.to_s] = location
        end

        def connect( model, target, opt={} )
          if opt.has_key? :all
            opt[:all] = URI(opt[:all])
            replace_server_if_needed( opt[:all] )
          end
          
          @transports ||= Hash.new
          
          logger.debug "setting up transport for model #{model}"
          uri = URI( target )
          @transports[model] = transport = spawn_transport( uri.scheme, opt )
          replace_server_if_needed( uri )
          transport.target_uri = uri
        end

        def replace_server_if_needed( uri )
          if not uri.host
            host, port = get_default_server(uri.scheme)
            uri.host = host
            uri.port = port unless port.nil?
          end
        end

        def spawn_transport( transport, opt={} )
          if @protocols and @protocols.has_key? transport.to_s
            @protocols[transport.to_s].new( opt )
          else
            raise "Unable to spawn transport object for transport '#{transport}'"
          end
        end

        def get_default_server( transport )
          ds = @default_servers[transport]
          if ds =~ /(.*?):(.*)/
            return $1, $2.to_i
          else
            return ds, nil
          end
        end

        def register_transport( klass, proto )
          @protocols ||= Hash.new
          if @protocols.has_key? proto
            #raise "Transport for protocol '#{proto}' already registered"
          else
            @protocols[proto] = klass
          end
        end

        def transport_for( model )
          @transports[model]
        end
      end
    end

    class << self
      def setup_transport
        yield TransportMap
      end

      def transport_for( model )
        TransportMap.transport_for model
      end

      def register_transport( klass, proto )
        TransportMap.register_transport klass, proto
      end
      
      def method_missing( sym, *args ) #:nodoc:
        attr_name = sym.to_s =~ /=$/ ? sym.to_s.sub(/.$/, '').to_sym : sym
        if DEFAULTS[attr_name]
          @config ||= Hash.new
          add_config_accessor(attr_name) unless self.respond_to? attr_name
          __send__( sym, *args )
        else
          super
        end
      end

      def add_config_accessor(sym) #:nodoc:
        instance_eval <<-END_EVAL
          def #{sym}
            if @config[#{sym.inspect}]
              return @config[#{sym.inspect}]
            else
              return DEFAULTS[#{sym.inspect}]
            end
          end

          def #{sym}=(val)
            @config[#{sym.inspect}] = val
          end
        END_EVAL
      end
    end
  end
end
