require 'xml'

module ActiveXML

  #basic outline of the xml parser abstraction
  module XMLAdapters
    # this adapter defines all available methods. specialized adapters subclass from it.
    # as much methods as possible should be implemented using more basic methods,
    # even if the implementations are unoptimized, so that the specialized adapters
    # can be implemented with low effort.
    class AbstractAdapter
      def has_element?( name )
      end

      def append_node( node )
      end
      alias_method '<<', :append_node

      def add_node_after( node, prev_name )
      end

      def add_node_before( node, succ_name )
      end

      def remove_node( node )
      end
    end

    class RexmlTreeAdapter < AbstractAdapter
    end

    class REXMLStreamAdapter < AbstractAdapter
    end
  end

  class LibXMLNode

    @@elements = {}

    class << self

      def setup
        @@logger = ActiveXML::Config.logger
      end

      def get_class(element_name)
        # FIXME: lines below don't work with relations. the related model has to
        # be pulled in when the relation is defined
        # 
        # axbase_subclasses = ActiveXML::Base.subclasses.map {|sc| sc.downcase}
        # if axbase_subclasses.include?( element_name )

        if @@elements.include? element_name
          return @@elements[element_name]
        end
        return ActiveXML::LibXMLNode
      end

      #creates an empty xml document
      # FIXME: works only for projects/packages, or by overwriting it in the model definition
      # FIXME: could get info somehow from schema, as soon as schema evaluation is built in
      def make_stub(opt)
        logger.debug "--> creating stub element for #{self.name}, arguments: #{opt.inspect}"
        if opt.nil?
          raise CreationError, "Tried to create document without opt parameter"
        end
        root_tag_name = self.name.downcase
        doc = XML::Document.new
        root = XML::Node.new root_tag_name
        doc.add_element root
        root.add_attribute 'name', opt[:name]
        root.add_attribute 'created', opt[:created_at] if opt[:created_at]
        root.add_attribute 'updated', opt[:updated_at] if opt[:updated_at]
        root.add_element XML::Node.new('title')
        root.add_element XML::Node.new('description')

        root
      end

      def logger
        ActiveXML::Config.logger
      end

      def handles_xml_element (*elements)
        elements.each do |elem|
          @@elements[elem] = self
        end
      end

      def xml_attr_reader (*attrs)
        attrs.each do |attr|
          class_eval do
            define_method(attr.to_s) do
              data.attributes[attr.to_s]
            end
          end
        end
      end

      def xml_attr_writer (*attrs)
        attrs.each do |attr|
          class_eval do
            define_method(attr.to_s+'=') do |new_value|
#              if data.attributes[attr.to_s].nil?
#                data.add_attribute attr.to_s, new_value.to_s
#              else
                data.attributes[attr.to_s] = new_value.to_s
#              end
            end
          end
        end
      end

      def xml_attr_accessor (*attrs)
        xml_attr_reader *attrs
        xml_attr_writer *attrs
      end

    end

    #instance methods

    attr_reader :data
    attr_accessor :throw_on_method_missing
    
    def initialize( data )
      if data.kind_of? XML::Node
        @data = data
      elsif data.kind_of? String
        self.raw_data = data
      elsif data.kind_of? Hash
        #create new
        @data = self.class.make_stub(data)
      else
        raise "constructor needs either XML::Node, String or Hash"
      end

      @throw_on_method_missing = true
      @node_cache = {}
    end

    def raw_data=( data )
      if data.kind_of? XML::Node
        @data = data.clone
      else
        if ActiveXML::Config.lazy_evaluation
          @raw_data = data.clone
        else
          begin
            @data = XML::Parser.string(data.to_str).parse.root
          rescue Object => e
            logger.error "Error parsing XML: #{e}"
            logger.error "XML content was: #{data}"
            raise e
          end
        end
      end
    end

    def element_name
      data.name
    end

    def data
      if !@data && @raw_data
         @data = XML::Parser.string(@raw_data.to_str).parse.root
      end
      @data
    end

    def text
      #puts 'text -%s- -%s-' % [data.inner_xml, data.content]
      data.content
    end

    def text= (what)
      data.content = what
    end

    def define_iterator_for_element( elem )
      logger.debug "2> starting to define iterator for element '#{elem}'"

      eval <<-end_eval
      def each_#{elem}
        return nil if not has_element? '#{elem}'
        result = Array.new
        data.elements.each('#{elem}') do |e|
          result << node = create_node_with_relations(e)
          yield node if block_given?
        end
        result
      end
      end_eval
    end
    #private :define_iterator_for_element


    def each
      result = Array.new
      data.each_element do |e|
        result << node = create_node_with_relations(e)
        yield node if block_given?
      end
      return result
    end


    def logger
      self.class.logger
    end

    def to_s
      # rexml: data.texts.map {|t| t.value}.to_s or ""
      ret = ''
      data.each do |node|
        if node.node_type == LibXML::XML::Node::TEXT_NODE
	   ret += node.content
	end
      end
      ret
    end

    def marshal_dump
      { 'throw' => @throw_on_method_missing, 'cache' => @node_cache, 
        'raw' => @raw_data }
    end

    def marshal_load(data)
      @throw_on_method_missing = data['throw']
      @node_cache = data['cache']
      @data = nil
      @raw_data = data['raw']
    end

    def dump_xml
      if @data.nil?
        @raw_data
      else
        data.to_s
      end
    end

    def to_param
      data.attributes['name']
    end

    def add_element ( element, attrs=nil )
      #puts 'before ' + data.to_s
      raise "First argument must be an element name" if element.nil?
      #puts data.inspect
      el = XML::Node.new(element)
      data << el
      attrs.each do |key, value|
        el.attributes[key]=value
      end if attrs.kind_of? Hash
      #puts 'after ' + data.to_s
      LibXMLNode.new(el)
    end
    
    #tests if a child element exists matching the given query.
    #query can either be an element name, an xpath, or any object
    #whose to_s method evaluates to an element name or xpath
    def has_element?( query )
      not data.find_first(query.to_s).nil?
    end

    def has_elements?
      # need to check for actual elements. Just a children can also mean
      # text node
      data.each_element { |e| return true }
      return false
    end
    
    def has_attribute?( query )
      not data.attributes.get_attribute(query).nil?
    end

    def has_attributes?
      data.attributes?
    end
    
    def delete_attribute( name )
      data.attributes.get_attribute(name).remove!
    end

    def delete_element( elem )
      if elem.kind_of? Node
          data.delete_element elem.data
      else
      	data.delete_element elem.to_s
      end
    end
    
    #removes all elements after the last named from @data and return in list
    def split_data_after( element_name )
      return false if not element_name

      element_name = element_name.to_s

      state = :before_element
      elem_cache = []
      data.each_element do |elem|
        case state
        when :before_element
          next if elem.name != element_name
          state = :element
          redo
        when :element
          next if elem.name == element_name
          state = :after_element
          redo
        when :after_element
          elem_cache << elem
          data.delete_element elem
        end
      end

      elem_cache
    end

    def merge_data( elem_list )
      elem_list.each do |elem|
        data.add_element elem
      end
    end

    def create_node_with_relations( element )
      #FIXME: relation stuff should be taken into an extra module
      #puts element.name
      klass = self.class.get_class(element.name)
      opt = {}
      node = nil
      node ||= klass.new(element)
      #logger.debug "created node: #{node.inspect}"
      return node
    end

    def method_missing( symbol, *args, &block )
      #logger.debug "called method: #{symbol}(#{args.map do |a| a.inspect end.join ', '})"

      symbols = symbol.to_s
      if( symbols =~ /^each_(.*)$/ )
        elem = $1
        query = args[0]
        if query
          elem = "#{elem}[#{query}]"
        end
        return [] if not has_element? elem
        result = Array.new
        data.find(elem).each do |e|
          result << node = create_node_with_relations(e)
          block.call(node) if block
        end
        return result
      end

      return nil unless data

      if data.attributes[symbols] 
        return data.attributes[symbols]
      end

      if !data.find_first(symbols).nil?
        xpath = args.shift
        query = xpath ? "#{symbol}[#{xpath}]" : symbols
        #logger.debug "method_missing: query is '#{query}'"
        if @node_cache[query]
          node = @node_cache[query]
          #logger.debug "taking from cache: #{node.inspect.to_s.slice(0..100)}"
        else
          e = data.find_first(query)
          return nil if e.nil?

          node = create_node_with_relations(e)
          
          @node_cache[query] = node
        end
        return node
      end
      
      return unless @throw_on_method_missing
      super( symbol, *args )
    end
  end

  class XMLNode < LibXMLNode
  end

end
