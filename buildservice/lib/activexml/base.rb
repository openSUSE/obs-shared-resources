module ActiveXML
  class GeneralError < StandardError; end
  class NotFoundError < GeneralError; end
  class CreationError < GeneralError; end
  class ParseError < GeneralError; end

  class Base < LibXMLNode

    include ActiveXML::Config

    # need it for test case
    attr_reader :init_options

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

      def find( *args )
        #FIXME: needs cleanup
        #TODO: factor out xml stuff to ActiveXML::Node
        #logger.debug "#{self.name}.find( #{args.map {|a| a.inspect}.join(', ')} )"

        args[1] ||= {}
        opt = args[0].kind_of?(Hash) ? args[0] : args[1]
        opt[@default_find_parameter] = args[0] if( args[0].kind_of? String )

        #logger.debug "prepared find args: #{args.inspect}"

        #TODO: somehow we need to set the transport again, as it was not set when subclassing.
        # only happens with rails >= 2.3.4 and config.cache_classes = true
        transport = config.transport_for(self.name.downcase.to_sym)
        raise "No transport defined for model #{self.name}" unless transport
        begin
          transport.find( self, *args )
        rescue ActiveXML::Transport::NotFoundError
          logger.debug "#{self.name}.find( #{args.map {|a| a.inspect}.join(', ')} ) did not find anything, return nil"
          return nil
        end
      end

      def find_cached( *args )
        opts = args.last if args.last.kind_of?(Hash) and args.last[:expires_in]
        opts = {:expires_in => 30.minutes}.merge( opts || Hash.new )
        cache_key = self.name + '-' + args.to_s
        if !(results = Rails.cache.read(cache_key))
          results = find( *args )
          Rails.cache.write(cache_key, results, :expires_in => opts[:expires_in]) if results
        end
      results
      end

      def free_cache( *args )
        cache_key = self.name + '-' + args.to_s
        Rails.cache.delete(cache_key)
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
      end
      return true
    end

    def delete(opt={})
      logger.debug "Delete #{self.class}, opt: #{opt.inspect}"
      transport = TransportMap.transport_for(self.class.name.downcase.to_sym)
      transport.delete self, opt
      return true
    end

  end
end
