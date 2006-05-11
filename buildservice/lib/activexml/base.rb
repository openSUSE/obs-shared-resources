require 'activexml/node'
require 'opensuse/frontend'

module ActiveXML
  class GeneralError < StandardError; end
  class NotFoundError < GeneralError; end
  class CreationError < GeneralError; end

  class Base < Node
    @default_find_parameter = :name

    class << self #class methods

      #transport object, gets defined according to configuration when Base is subclassed
      attr_reader :transport
      
      def inherited( subclass )
        # called when a subclass is defined
        logger.debug "initializing model #{subclass}"

        # setup transport object for this model
        subclass.instance_variable_set "@transport", config.transport_for(subclass.name.downcase.to_sym)
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
        logger.debug "belongs_to #{tag_list.inspect}"
        @rel_belongs_to ||= Array.new
        @rel_belongs_to.concat(tag_list).uniq!
      end

      def has_many(*tag_list)
        logger.debug "has_many #{tag_list.inspect}"
        @rel_has_many ||= Array.new
        @rel_has_many.concat(tag_list).uniq!
      end

      def error
        @error
      end

      def find( *args )
        #FIXME: needs cleanup
        #TODO: factor out xml stuff to ActiveXML::Node
        logger.debug "#{self.name}.find( #{args.map {|a| a.inspect}.join(', ')} )"

        args[1] ||= {}
        opt = args[0].kind_of?(Hash) ? args[0] : args[1]
        opt[@default_find_parameter] = args[0] if( args[0].kind_of? String )

        STDERR.puts "prepared find args: #{args.inspect}"
        
        raise "No transport defined for model #{self.name}" unless transport
        transport.find( self, *args )
        
=begin
        data_doc = REXML::Document.new( data ).root
        logger.debug "DATA #{data}"

        if( %w{projectlist packagelist platforms directory}.include? data_doc.name )
          result = []
          data_doc.elements.each do |e|
            result << self.new(e, opt)
          end
        else
          result = self.new(data_doc, opt)
        end
        result
=end
      end
    end #class methods

    def initialize( data, opt={} )
      super(data)
      opt = data if data.kind_of? Hash and opt.empty?

      @init_options = opt
      
      #FIXME: hack
      #if( rel = self.class.instance_variable_get("@rel_belongs_to") )
      #  rel.each do |var|
      #    raise "relation parameter not specified (was looking for #{var.inspect})" unless opt[var]
      #  self.instance_variable_set( "@#{var}", opt[var] )
      #  end
      #end
    end

    def name
      method_missing( :name )
    end

    def save
      logger.debug "Save #{self.class}"

      logger.debug "XML #{@data}"

      put_opt = {}
     
      self.class.transport.save self

      #if self.class.name == "Person"
      #  put_opt[:login] = self.login
      #  @@transport.put_user @data.to_s, put_opt
      #elsif self.class.name == "Platform"
      #  put_opt[:platform] = self.name
      #  put_opt[:project] = self.project
      #  @@transport.put_platform @data.to_s, put_opt
      #else
      #  put_opt[self.class.name.downcase.to_sym] = self.name
      #
      #  #FIXME: slightly less hackish, at least the interface is right. nevertheless still a hack
      #  if( rel = self.class.instance_variable_get( "@rel_belongs_to" ) )
      #    rel.each do |var|
      #      put_opt[var] = instance_variable_get( "@#{var}" )
      #    end
      #  end

      #  @@transport.put_meta @data.to_s, put_opt
      #end
      return true
    end
  end
end
