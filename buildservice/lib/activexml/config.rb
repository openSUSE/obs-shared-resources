module ActiveXML
  module Config

    DEFAULTS = Hash.new
    DEFAULTS[:xml_backend] = "rexml"

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

    class << self
      def method_missing( sym, *args ) #:nodoc:
        if DEFAULTS[sym]
          @config ||= Hash.new
          add_config_accessor(sym) unless self.respond_to? sym
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
