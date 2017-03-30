# frozen_string_literal: true

module DAV4Rack
  module XmlElements

    DAV_NAMESPACE      = 'DAV:'
    DAV_NAMESPACE_NAME = 'D'
    DAV_XML_NS         = 'xmlns:D'

    XML_VERSION = '1.0'

    %w(
      activelock
      depth
      href
      lockdiscovery
      lockentry
      lockroot
      lockscope
      locktoken
      locktype
      multistatus
      owner
      prop
      propstat
      response
      status
      timeout
    ).each do |name|
      const_set "D_#{name.upcase}", "#{DAV_NAMESPACE_NAME}:#{name}"
    end

    INFINITY = 'infinity'
    ZERO = '0'

    def ox_element(name, content = nil)
      e = Ox::Element.new(name)
      if content
        e << content
      end
      e
    end

    def ox_append(element, value, prefix: DAV_NAMESPACE_NAME)
      case value
      when Ox::Element
        element << value
      when Symbol
        element << Ox::Element.new("#{prefix}:#{value}")
      when Enumerable
        value.each{|v| ox_append element, v, prefix: prefix }
      else
        element << value.to_s if value
      end
    end

    def ox_lockentry(scope, type)
      Ox::Element.new(D_LOCKENTRY).tap do |e|
        e << ox_element(D_LOCKSCOPE, Ox::Element.new(scope))
        e << ox_element(D_LOCKTYPE,  Ox::Element.new(type))
      end
    end

    # returns an activelock Ox::Element for the given lock data
    def ox_activelock(time: nil, token:, depth:,
                      scope: nil, type: nil, owner: nil, root: nil)

      Ox::Element.new(D_ACTIVELOCK).tap do |activelock|
        if scope
          activelock << ox_element(D_LOCKSCOPE, scope)
        end
        if type
          activelock << ox_element(D_LOCKTYPE, type)
        end
        activelock << ox_element(D_DEPTH, depth)
        activelock << ox_element(D_TIMEOUT,
                                 (time ? "Second-#{time}" : INFINITY))

        token = ox_element(D_HREF, token)
        activelock << ox_element(D_LOCKTOKEN, token)

        if owner
          activelock << ox_element(D_OWNER, owner)
        end

        if root
          root = ox_element(D_HREF, root)
          activelock << ox_element(D_LOCKROOT, root)
        end
      end

    end

    # block is called for each element (at least self, depending on depth also
    # with children / further descendants)
    def xml_with_depth(resource, depth, &block)
      partial_document = Ox::Document.new()

      yield resource, partial_document

      case depth
      when 0
      when 1
        resource.children.each do |child|
          yield child, partial_document
        end
      else
        resource.descendants.each do |desc|
          yield desc, partial_document
        end
      end

      Ox.dump(partial_document, {indent: -1})
    end


  end
end
