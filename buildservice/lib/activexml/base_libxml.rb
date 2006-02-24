#require 'opensuse/frontend'
require 'rexml/document'
require 'xml/libxml'
require 'tempfile'
require 'digest/md5'

class XML::Document
  class << self
    def string( content )
      Kernel.srand content.object_id
      tf_prefix = "xml_document_string." + Digest::MD5.hexdigest( content + Kernel.rand.to_s ) + "."
      tf = Tempfile.new(tf_prefix)
      tf.print content
      tf.rewind
      doc = file( tf.path )
      tf.unlink
      doc
    end
  end
end

module ActiveXML
  class RecordNotFoundError
  end

  class CreationError
  end

  class Base
    class << self #class methods
      def setup(transport_object)
        @@transport = transport_object
        @@logger = RAILS_DEFAULT_LOGGER
        logger.debug "--> ActiveXML successfully set up"
        true
      end

      def get_class(element_name)
        #logger.debug( "get_class: #{element_name}" )
        #FIXME: implement this correctly
        if %w{package project result person platform}.include?( element_name )
          return Object.const_get( element_name.capitalize )
        end
        return ActiveXML::Base
      end

      #creates an empty xml document
      def make_stub(name)
        logger.debug "--> creating stub element for #{self.name}, name is: #{name}"
        if name.nil?
          raise CreationError, "Tried to create document without name parameter"
        end
        root_tag_name = self.name.downcase
        root = XML::Node.new(root_tag_name)
        root['name'] = name
        root << XML::Node.new('title')
        root << XML::Node.new('description')

        root
      end

      def logger
        @@logger
      end

      def error
        @error
      end

      def find( *args )
        #STDERR.puts "find args: #{args.inspect}"
        #FIXME: needs cleanup
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
          
          data_doc = XML::Document.string( data ).root.copy(true)
          #logger.debug "DATA #{data}"
        rescue Suse::Frontend::TransportError, Suse::Frontend::UnspecifiedError
          @error = $!
          return false
        end

        if( data_doc.name =~ /list$/ || data_doc.name == "platforms" )
          is_collection = true
          result = []
          data_doc.find('*').each do |e|
            if( wanted_name )
              logger.debug "find: trying to find #{self.name} with name #{wanted_name}"
              logger.debug "find: current name: #{e.attributes['name']}"
              next unless e['name'] == wanted_name
              logger.debug "find: found it"
              result = self.new(e)
              break
            end
            result << self.new(e)
          end
        else
          result = self.new(data_doc)
        end

        result
      end
      
    end #class methods

    attr_reader :data
    attr_accessor :throw_on_method_missing

    def initialize( data )
      if data.kind_of? XML::Node
        @data = data.copy(true)
      elsif data.kind_of? String
        @data = XML::Document.string( data ).root.copy(true)
      elsif data.kind_of? Hash
        #create new
        @data = self.class.make_stub(data[:name])
      else
        raise "constructor needs either XML::Node, String or Hash"
      end

      @throw_on_method_missing = true

      #collect unique element names
      element_names = []

      #FIXME: 
      doc = XML::Document.new
      doc.root = @data.copy(true)
      
      doc.root.find('*').each do |e|
        element_names.push e.name if not element_names.include? e.name
      end
      
      #STDERR.puts element_names.inspect

      #create an iterator for each element
      element_names.each do |name|
        eval <<-end_eval
          def each_#{name}
            result = @data.find('#{name}').to_a.each do |e|
              yield self.class.get_class(e.name).new(e) if block_given?
            end
            result.map {|e| self.class.get_class(e.name).new(e)}
          end
        end_eval
      end
    end

    def logger
      @@logger
    end

    def to_s
      if @data.child? and @data.child.text?
        return @data.child.to_s
      else
        return ""
      end
    end

    def dump_xml
      @data.to_s
    end

    def to_param
      @data['name']
    end

    #tests if a child element exists matching the given query.
    #query can either be an element name, an xpath, or any object
    #whose to_s method evaluates to an element name or xpath
    def has_element?( query )
      @data.find(query.to_s).length > 0
    end

    def name
      method_missing( :name )
    end

    #FIXME: project parameter is a hack, should be done with an association in the model
    #have to figure this out asap
    def save( project=nil )
      logger.debug "Save #{self.class}"

      put_opt = {}
      
      if self.class.name == "Person"
        put_opt[:login] = self.login
        @@transport.put_user @data.to_s, put_opt
      elsif self.class.name == "Platform"
        put_opt[:platform] = self.name
        @@transport.put_platform @data.to_s, put_opt
      else
        if project
          #this is a package
          put_opt[:project] = project
          put_opt[:package] = self.name
        else
          #this is a project
          put_opt[:project] = self.name
        end
        @@transport.put_meta @data.to_s, put_opt
      end
      true
    end

    #removes all elements after the last named from @data and return in list
    def split_data_after( element_name )
      return false if not element_name

      element_name = element_name.to_s

      #libxml cannot remove elements, so we have to copy the original document
      new_data = XML::Node.new( @data.name )
      split_data = XML::Node.new( 'splitdummy' )
      
      if @data.properties?
        prop = @data.properties
        begin
          new_data[prop.name] = prop.value
        end while prop = prop.next
      end
      
      state = :before_element
      child = @data.child
      begin
        case state
        when :before_element
          if child.name != element_name
            new_data << child.copy(true)
          else
            state = :element
            redo
          end
        when :element
          if child.name == element_name or child.text?
            new_data << child.copy(true)
          else
            state = :after_element
            redo
          end
        when :after_element
          split_data << child.copy(true)
        end
      end while child = child.next

      @data = new_data.copy(true)
      return split_data if split_data.child?
      nil
    end

    def merge_data( other_data )
      return nil if other_data.nil? or other_data.child?.nil?
      child = other_data.child
      begin
        @data << child.copy(true)
      end while child = child.next
    end

    def method_missing( symbol, *args )
      #logger.debug "called method: #{symbol}(#{args.map do |a| a.inspect end.join ', '})"

      if( @data[symbol.to_s] )
        return @data[symbol.to_s]
      end

      if( @data.find(symbol.to_s).length > 0 )
        xpath = args.shift
        query = xpath ? "#{symbol}[#{xpath}]" : symbol.to_s
        result = @data.find(query).to_a
        if result.nil?
          return nil
        else
          e = result[0]
          return self.class.get_class(e.name).new( e )
        end
      end
      return unless @throw_on_method_missing
      super( symbol, *args )
    end
  end
end
