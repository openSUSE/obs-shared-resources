require 'nokogiri'

module ActiveXML

  class LibXMLNode

    @@elements = {}

    class << self

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
        #logger.debug "--> creating stub element for #{self.name}, arguments: #{opt.inspect}"
        if opt.nil?
          raise CreationError, "Tried to create document without opt parameter"
        end
        root_tag_name = self.name.downcase
        doc = ActiveXML::Base.new("<#{root_tag_name}/>")
        doc.set_attribute('name', opt[:name])
        doc.set_attribute('created', opt[:created_at]) if opt[:created_at]
        doc.set_attribute('updated', opt[:updated_at]) if opt[:updated_at]
        doc.add_element 'title'
        doc.add_element 'description'
        doc
      end

      def logger
        ActiveXML::Config.logger
      end

      def handles_xml_element (*elements)
        elements.each do |elem|
          @@elements[elem] = self
        end
      end

    end

    #instance methods

    attr_reader :data
    attr_accessor :throw_on_method_missing

    def initialize( data )
      if data.kind_of? Nokogiri::XML::Node
        @data = data
      elsif data.kind_of? String
        self.raw_data = data.clone
      elsif data.kind_of? Hash
        #create new
        stub = self.class.make_stub(data)
        if stub.kind_of? String
          self.raw_data = stub
        elsif stub.kind_of? LibXMLNode
          self.raw_data = stub.dump_xml
        else
          raise "make_stub should return LibXMLNode or String, was #{stub.inspect}"
        end
      elsif data.kind_of? LibXMLNode
        @data = data.internal_data.clone
      else
        raise "constructor needs either XML::Node, String or Hash"
      end

      @throw_on_method_missing = true
      @node_cache = {}
    end

    def parse(data)
      raise ParseError.new('Empty XML passed!') if data.empty?
      begin
        @data = Nokogiri::XML::Document.parse(data.to_str.strip, nil, nil, Nokogiri::XML::ParseOptions::STRICT).root
      rescue Nokogiri::XML::SyntaxError => e
        logger.error "Error parsing XML: #{e}"
        logger.error "XML content was: #{data}"
        raise ParseError.new e.message
      end
    end
    private :parse

    def raw_data=( data )
      if data.kind_of? Nokogiri::XML::Node
        @data = data.clone
      else
        if ActiveXML::Config.lazy_evaluation
          @raw_data = data.clone
          @data = nil
        else
          parse(data)
        end
      end
    end

    def element_name
      data.name
    end

    def element_name=(name)
      data.name = name
    end

    def data
      if !@data && @raw_data
        parse(@raw_data)
        # save memory
        @raw_data = nil
      end
      @data
    end
    private :data

    def text
      #puts 'text -%s- -%s-' % [data.inner_xml, data.content]
      data.content
    end

    def text= (what)
      data.content = what.to_xs
    end

    def each(symbol = nil)
      result = Array.new
      each_with_index(symbol) do |node, index|
        result << node
        yield node if block_given?
      end
      return result
    end

    def each_with_index(symbol = nil)
      unless block_given?
        raise "use each instead"
      end
      index = 0
      if symbol.nil?
        nodes = data.element_children
      else
        nodes = data.xpath(symbol.to_s)
      end
      nodes.each do |e|
        yield create_node_with_relations(e), index
        index = index + 1
      end
      nil
    end

    def find_first(symbol)
      n = data.xpath(symbol.to_s).first
      if n 
        return create_node_with_relations(n)
      else
        return nil
      end
    end

    def logger
      self.class.logger
    end

    def to_s
      ret = ''
      data.children.each do |node|
        if node.text?
          ret += node.content
        end
      end
      ret
    end

    def marshal_dump
      [@throw_on_method_missing, @node_cache, dump_xml]
    end

    def marshal_load(dumped)
      @throw_on_method_missing, @node_cache, @raw_data = dumped
      @data = nil
    end

    def dump_xml
      if @data.nil?
        @raw_data
      else
        data.to_s
      end
    end

    def to_param
      data.attributes['name'].value
    end

    def add_node(node)
      raise ArgumentError, "argument must be a string" unless node.kind_of? String
      xmlnode = Nokogiri::XML::Document.parse(node, nil, nil, Nokogiri::XML::ParseOptions::STRICT).root
      data.add_child(xmlnode)
      xmlnode
    end

    def add_element ( element, attrs=nil )
      raise "First argument must be an element name" if element.nil?
      el = data.document.create_element(element)
      data.add_child(el)
      attrs.each do |key, value|
        el[key]=value
      end if attrs.kind_of? Hash
      LibXMLNode.new(el)
    end

    #tests if a child element exists matching the given query.
    #query can either be an element name, an xpath, or any object
    #whose to_s method evaluates to an element name or xpath
    def has_element?( query )
      !data.xpath(query.to_s).empty?
    end

    def has_elements?
      return !data.element_children.empty?
    end

    def has_attribute?( query )
      data.attributes.has_key?(query.to_s)
    end

    def has_attributes?
      !data.attribute_nodes.empty?
    end

    def delete_attribute( name )
      data.remove_attribute(name.to_s)
    end

    def delete_element( elem )
      if elem.kind_of? LibXMLNode
        raise "NO GOOD IDEA!" unless self.internal_data.document == elem.internal_data.document
        elem.internal_data.remove
      elsif elem.kind_of? Nokogiri::XML::Node
        raise "this should be obsolete!!!"
        elem.remove
      else
        logger.warn "delete_element called with xpath #{elem}!!"
        e = data.xpath(elem.to_s)
        if e.kind_of? Nokogiri::XML::Node
          e.remove
          return
        end
        raise RuntimeError, "this should be obsolete!!!"
      end
    end

    def set_attribute( name, value)
       data[name] = value
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

    def value( symbol ) 
      return nil unless data

      symbols = symbol.to_s

      if data.attributes.has_key?(symbols)
        return data.attributes[symbols].value
      end

      elem = data.xpath(symbols)
      unless elem.empty?
        return elem.first.inner_text
      end

      return nil
    end

    def find( symbol, &block ) 
       symbols = symbol.to_s
       data.xpath(symbols).each do |e|
         block.call(create_node_with_relations(e))
       end 
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
        data.xpath(elem).each do |e|
          result << node = create_node_with_relations(e)
          block.call(node) if block
        end
        return result
      end

      return nil unless data

      if data.attributes[symbols]
        return data.attributes[symbols].value
      end

      begin
        datasym = data.xpath(symbols)
      rescue Nokogiri::XML::XPath::SyntaxError
        return unless @throw_on_method_missing
        super( symbol, *args )
      end
      unless datasym.empty?
        datasym = datasym.first
        xpath = args.shift
        query = xpath ? "#{symbol}[#{xpath}]" : symbols
        #logger.debug "method_missing: query is '#{query}'"
        if @node_cache[query]
          node = @node_cache[query]
          #logger.debug "taking from cache: #{node.inspect.to_s.slice(0..100)}"
        else
          e = data.xpath(query)
          return nil if e.empty?

          node = create_node_with_relations(e.first)

          @node_cache[query] = node
        end
        return node
      end

      return unless @throw_on_method_missing
      super( symbol, *args )
    end

    # stay away from this
    def internal_data #nodoc
      data
    end
    protected :internal_data
  end

  class XMLNode < LibXMLNode
  end

end
