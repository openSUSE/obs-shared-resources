require 'activexml/node'
require 'opensuse/frontend'

module ActiveXML
  class GeneralError < StandardError; end
  class NotFoundError < GeneralError; end
  class CreationError < GeneralError; end

  class Base < Node
    class << self #class methods

      #transport object, gets defined according to configuration when Base is subclassed
      attr_reader :transport
      
      def inherited( subclass )
        # called when a subclass is defined
        logger.debug "initializing model #{subclass}"

        # setup transport object for this model
        subclass.instance_variable_set "@transport", config.transport_for(subclass.name.downcase.to_sym)
      end
      private :inherited

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
        if( args[0].kind_of? String )
          wanted_name = args.shift
          logger.debug "find: restrict to name: #{wanted_name}, object: #{self.name}"
        else
          wanted_name = nil
        end

        opt = args.shift || {}
        #STDERR.puts "find opts: #{opt.inspect}, wanted_name: #{wanted_name}"
        
        begin
          if ActiveXML::Config.use_transport_plugins
            raise "No transport defined for model #{self.name}" unless transport
            data = transport.find( opt )
          else
            if self.name == "Result"
              data = @@transport.get_result( opt )
            elsif self.name == "Platform"
              case opt.class.name
              when /Symbol/
                throw "Illegal Symbol in find parameters: need ':all'" if opt != :all
                data = @@transport.get_platform
              when /Hash/
                opt[self.name.downcase.to_sym] = wanted_name if wanted_name
                data = @@transport.get_platform( opt )
              else
                throw "Illegal parameters for find: need Symbol ':all' or Hash"
              end
            elsif self.name == "Person"
              data = @@transport.get_user( opt )
            elsif self.name == "Directory"
              data = @@transport.get_source( opt )
            else
              case opt.class.name
              when /Symbol/
                throw "Illegal Symbol in find parameters: need ':all'" if opt != :all
                data = @@transport.get_source
              when /Hash/
                opt[self.name.downcase.to_sym] = wanted_name if wanted_name
                data = @@transport.get_meta( opt )
              else
                throw "Illegal parameters for find: need Symbol ':all' or Hash"
              end
            end
          end

          data_doc = REXML::Document.new( data ).root
          logger.debug "DATA #{data}"
        rescue Suse::Frontend::UnspecifiedError
          raise NotFoundError, $!.message
        end

        if( %w{projectlist packagelist platforms directory}.include? data_doc.name )
          is_collection = true
          result = []
          data_doc.elements.each do |e|
            if( wanted_name )
              logger.debug "find: trying to find #{self.name} with name #{wanted_name}"
              logger.debug "find: current name: #{e.attributes['name']}"
              next unless e.attributes['name'] == wanted_name
              logger.debug "find: found it"
              result = self.new(e, opt)
              break
            end
            result << self.new(e, opt)
          end
        else
          result = self.new(data_doc, opt)
        end

        result
      end
    end #class methods

    def initialize( data, opt={} )
      super(data)
      opt = data if data.kind_of? Hash and opt.empty?
      #FIXME: hack
      if( rel = self.class.instance_variable_get("@rel_belongs_to") )
        rel.each do |var|
          raise "relation parameter not specified (was looking for #{var.inspect})" unless opt[var]
          self.instance_variable_set( "@#{var}", opt[var] )
        end
      end
    end

    def name
      method_missing( :name )
    end

    def save
      logger.debug "Save #{self.class}"

      logger.debug "XML #{@data}"

      put_opt = {}
      
      if self.class.name == "Person"
        put_opt[:login] = self.login
        @@transport.put_user @data.to_s, put_opt
      elsif self.class.name == "Platform"
        put_opt[:platform] = self.name
        put_opt[:project] = self.project
        @@transport.put_platform @data.to_s, put_opt
      else
        put_opt[self.class.name.downcase.to_sym] = self.name

        #FIXME: slightly less hackish, at least the interface is right. nevertheless still a hack
        if( rel = self.class.instance_variable_get( "@rel_belongs_to" ) )
          rel.each do |var|
            put_opt[var] = instance_variable_get( "@#{var}" )
          end
        end

        @@transport.put_meta @data.to_s, put_opt
      end
      true
    end
  end
end
