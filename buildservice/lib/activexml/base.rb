module ActiveXML
  class GeneralError < StandardError; end
  class NotFoundError < GeneralError; end
  class CreationError < GeneralError; end
  class ParseError < GeneralError; end

  class Base < LibXMLNode

    include ActiveXML::Config

    attr_reader :init_options
    attr_reader :cache_key

    @default_find_parameter = :name

    class << self #class methods

      #transport object, gets defined according to configuration when Base is subclassed
      attr_reader :transport

      def inherited( subclass )
        # called when a subclass is defined
        #logger.debug "Initializing ActiveXML model #{subclass}"
        subclass.instance_variable_set "@default_find_parameter", @default_find_parameter
      end
      private :inherited

      # setup the default parameter for find calls. If the first parameter to <Model>.find is a string,
      # the value of this string is used as value f
      def default_find_parameter( sym )
        @default_find_parameter = sym
      end

      def setup(transport_object)
        super()
        @@transport = transport_object
        logger.debug "--> ActiveXML successfully set up"
        true
      end

      def belongs_to(*tag_list)
        logger.debug "#{self.name} belongs_to #{tag_list.inspect}"
        @rel_belongs_to ||= Array.new
        @rel_belongs_to.concat(tag_list).uniq!
      end

      def has_many(*tag_list)
        #logger.debug "#{self.name} has_many #{tag_list.inspect}"
        @rel_has_many ||= Array.new
        @rel_has_many.concat(tag_list).uniq!
      end

      def error
        @error
      end

      def prepare_args( args )
        if args[0].kind_of? String
          args[1] ||= {}
          first_arg = args.shift
          hash = args.shift
          hash[@default_find_parameter] = first_arg
          args.insert(0, hash)
        end
        if args[0].kind_of? Hash
          hash = Hash.new
          args[0].each do |key, value|
            if key.nil? or value.nil?
              logger.debug "nil value given #{args.inspect}"
              next
            end
            if value.kind_of? Array
              hash[key.to_sym] = value
            else
              hash[key.to_sym] = value.to_s 
            end
          end
          args[0] = hash
        end

        #logger.debug "prepared find args: #{args.inspect}"
        return args
      end

      def calc_key( args )
        #logger.debug "Cache key for #{args.inspect}"
        self.name + "_" + MD5::md5( args.to_s ).to_s
      end

      def find_priv(cache_time, args )
        #FIXME: needs cleanup
        #TODO: factor out xml stuff to ActiveXML::Node
        logger.debug "#{self.name}.find( #{args.inspect})"

        #TODO: somehow we need to set the transport again, as it was not set when subclassing.
        # only happens with rails >= 2.3.4 and config.cache_classes = true
        transport = config.transport_for(self.name.downcase.to_sym)
        raise "No transport defined for model #{self.name}" unless transport
        begin
          if cache_time
            cache_key = calc_key( args )
            objdata, params = Rails.cache.fetch(cache_key, :expires_in => cache_time) do
              transport.find( self, *args )
            end
          else
            objdata, params = transport.find( self, *args )
          end
          begin
            obj = self.new( objdata )
          rescue ActiveXML::ParseError => e
            raise "Parsing XML failed: #{e.message}"
          end
          obj.instance_variable_set( '@init_options', params )
          obj.instance_variable_set( '@cache_key', calc_key( args ) ) if cache_time
          return obj
        rescue ActiveXML::Transport::NotFoundError
          logger.debug "#{self.name}.find( #{args.map {|a| a.inspect}.join(', ')} ) did not find anything, return nil"
          return nil
        end
      end

      def find( *args )
        find_priv(nil, prepare_args(args) )
      end

      def find_cached( *args )
        expires_in = 30.minutes
        if args.last.kind_of?(Hash) and args.last[:expires_in]
          expires_in = args.last[:expires_in] 
          args.last.delete :expires_in
        end
        find_priv(expires_in, prepare_args(args))
      end

      def free_cache( *args )
        args = prepare_args( args)
        #logger.debug "#{self.name}.free( #{args.inspect})"
        Rails.cache.delete( calc_key( args ) )
      end

    end #class methods

    def initialize( data, opt={} )
      super(data)
      opt = data if data.kind_of? Hash and opt.empty?
      @init_options = opt
    end

    def name
      method_missing( :name )
    end

    def marshal_dump
      a = super
      a.push(@init_options)
    end

    def marshal_load(dumped)
      super
      @init_options = *dumped.shift(1)
    end

    def save(opt={})
      transport = TransportMap.transport_for(self.class.name.downcase.to_sym)
      if opt[:create]
        @raw_data = transport.create self, opt
        @data = nil
      else
        transport.save self, opt
        Rails.cache.delete @cache_key if @cache_key
      end
      return true
    end

    def delete(opt={})
      logger.debug "Delete #{self.class}, opt: #{opt.inspect}"
      transport = TransportMap.transport_for(self.class.name.downcase.to_sym)
      transport.delete self, opt
      Rails.cache.delete @cache_key if @cache_key
      return true
    end

  end
end
