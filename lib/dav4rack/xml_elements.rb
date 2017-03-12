module DAV4Rack
  module XmlElements

    DAV_NAMESPACE = 'DAV:'
    DAV_NAMESPACE_NAME = 'D'

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
      const_set "D_#{name.upcase}", "#{DAV_NAMESPACE_NAME}:#{name}".freeze
    end

    INFINITY = 'infinity'.freeze
    ZERO = '0'.freeze

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
        activelock << ox_element(D_LOCKTOKEN, token)
        if owner
          activelock << ox_element(D_OWNER, owner)
        end
        if root
          activelock << ox_element(D_LOCKROOT, root)
        end
      end

    end

  end
end
