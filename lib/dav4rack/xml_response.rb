# frozen_string_literal: true

module DAV4Rack
  class XmlResponse
    include XmlElements

    def initialize(response, namespaces, http_version: 'HTTP/1.1')
      @response = response
      @namespaces = namespaces
      @http_version = http_version
    end

    def render_xml(xml_body)
      @namespaces.each do |href, prefix|
        xml_body["xmlns:#{prefix}"] = href
      end

      xml_doc = Ox::Document.new(:version => '1.0')
      xml_doc << xml_body

      @response.body = Ox.dump(xml_doc, {indent: -1, with_xml: true})

      @response["Content-Type"] = 'application/xml; charset=utf-8'
      @response["Content-Length"] = @response.body.bytesize.to_s
    end


    def multistatus
      multistatus = Ox::Element.new(D_MULTISTATUS)
      yield multistatus
      render_xml multistatus
    end


    def render_failed_precondition(status, href)
      error = Ox::Element.new(D_ERROR)
      case status.code
      when 423
        l = Ox::Element.new(D_LOCK_TOKEN_SUBMITTED)
        l << ox_element(D_HREF, href)
        error << l
      end
      render_xml error
    end


    def render_lock_errors(errors)
      multistatus do |xml|
        errors.each do |href, status|
          r = response href, status
          if status.code == 423
            r << ox_element(D_ERROR, Ox::Element.new(D_LOCK_TOKEN_SUBMITTED))
          end
          xml << r
        end
      end
    end


    def render_lockdiscovery(*args)
      render_xml ox_element(D_PROP,
                            ox_element(D_LOCKDISCOVERY,
                                       ox_activelock(*args))
                           )
    end


    #
    # helpers for creating single elements
    #



    def response(href, status)
      r = Ox::Element.new(D_RESPONSE)
      r << ox_element(D_HREF, href)
      r << self.status(status)
      r
    end

    def raw(xml)
      Ox::Raw.new xml
    end

    def status(status)
      ox_element D_STATUS, "#{@http_version} #{status.status_line}"
    end


  end
end
