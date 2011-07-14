require 'xml'

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
        logger.debug "--> creating stub element for #{self.name}, arguments: #{opt.inspect}"
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
      if data.kind_of? XML::Node
        @data = data
      elsif data.kind_of? String
        self.raw_data = data
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
        self.raw_data = data.dump_xml
      else
        raise "constructor needs either XML::Node, String or Hash"
      end

      @throw_on_method_missing = true
      @node_cache = {}
    end

    def parse(data)
      raise ParseError.new('Empty XML passed!') if data.empty?
      begin
        @data = XML::Parser.string(data.to_str.strip).parse.root
      rescue => e
        logger.error "Error parsing XML: #{e}"
        logger.error "XML content was: #{data}"
        raise ParseError.new e.message
      end
    end
    private :parse

    def raw_data=( data )
      if data.kind_of? XML::Node
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
      nodes = Array.new
      if symbol.nil?
        data.each_element { |e| nodes << e }
      else
        data.find(symbol.to_s).each { |e| nodes << e }
      end
      nodes.each do |e|
        yield create_node_with_relations(e), index
        index = index + 1
      end
    end

    def find_first(symbol)
      data.find(symbol.to_s).each do |e|
        return create_node_with_relations(e)
      end
      return nil
    end

    def logger
      self.class.logger
    end

    def to_s
      ret = ''
      data.each do |node|
        if node.node_type == LibXML::XML::Node::TEXT_NODE
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
      data.attributes['name']
    end

    def add_node(node)
      raise ArgumentError, "argument must be a string" unless node.kind_of? String
      xmlnode = data.doc.import(XML::Parser.string(node.to_s).parse.root)
      data << xmlnode
      xmlnode
    end

    def add_element ( element, attrs=nil )
      raise "First argument must be an element name" if element.nil?
      el = XML::Node.new(element)
      data << el
      attrs.each do |key, value|
        el.attributes[key]=value
      end if attrs.kind_of? Hash
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
      if elem.kind_of? LibXMLNode
        raise "NO GOOD IDEA!" unless self.internal_data.doc == elem.internal_data.doc
        elem.internal_data.remove!
      elsif elem.kind_of? LibXML::XML::Node
        raise "this should be obsolete!!!"
        elem.remove!
      else
        e = data.find_first(elem.to_s)
        e.remove! if e
      end
    end

    def set_attribute( name, value)
       data.attributes[name] = value
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

    def value( symbol) 
      return nil unless data

      symbols = symbol.to_s

      if data.attributes[symbols]
        return data.attributes[symbols]
      end

      elem = data.find_first(symbols)
      if elem
        return elem.content
      end

      return nil
    end

    def method_missing( symbol, *args, &block )
      logger.debug "called method: #{symbol}(#{args.map do |a| a.inspect end.join ', '})"

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

      begin
        datasym = data.find_first(symbols)
      rescue LibXML::XML::Error
        return unless @throw_on_method_missing
        super( symbol, *args )
      end
      unless datasym.nil?
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

    # stay away from this
    def internal_data #nodoc
      data
    end
    protected :internal_data
  end

  class XMLNode < LibXMLNode
  end

end

LibXML::XML::Error.set_handler(&LibXML::XML::Error::QUIET_HANDLER)
