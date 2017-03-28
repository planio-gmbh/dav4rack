# frozen_string_literal: true

require 'uri'
require 'dav4rack/http_status'
require 'dav4rack/xml_elements'

module DAV4Rack

  class Controller
    include DAV4Rack::HTTPStatus
    include DAV4Rack::Utils
    include DAV4Rack::XmlElements

    XML_CONTENT_TYPE = 'application/xml; charset=utf-8'

    attr_reader :request, :response, :resource


    # request:: Rack::Request
    # response:: Rack::Response
    # options:: Options hash
    # Create a new Controller.
    # NOTE: options will be passed to Resource
    def initialize(request, response, options={})
      request.path_info = ::File.expand_path(request.path_info) if request.path_info.length > 0
      @request = request
      @request_path = request.path.force_encoding 'UTF-8'
      @response = response
      @options = options

      @dav_extensions = options[:dav_extensions]
      @always_include_dav_header = options[:always_include_dav_header]

      @resource = resource_class.new(actual_path, implied_path, request, response, options)

      if(@always_include_dav_header)
        add_dav_header
      end
    end

    # s:: string
    # Unescape URL string
    def url_unescape(s)
      URI.unescape(s)
    end

    def add_dav_header
      unless(response['Dav'])
        dav_support = ['1']
        if !@always_include_dav_header || resource.supports_locking?
          # compliance is resource specific, only advertise 2 (locking) if
          # supported on the resource. If the header is only set on OPTIONS
          # responses, advertise locking anyway
          dav_support << '2'
        end
        dav_support += @dav_extensions if @dav_extensions
        response['Dav'] = dav_support * ', '
      end
    end

    # Return response to OPTIONS
    def options
      status = resource.options request, response
      if(status == OK)
        add_dav_header
        response['Allow'] ||= 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
        response['Ms-Author-Via'] ||= 'DAV'
      end
      status
    end

    # Return response to HEAD
    def head
      if(resource.exist?)
        response['Etag'] = resource.etag
        response['Content-Type'] = resource.content_type
        response['Content-Length'] = resource.content_length.to_s
        response['Last-Modified'] = resource.last_modified.httpdate
        resource.head(request, response)
        OK
      else
        NotFound
      end
    end

    # Return response to GET
    def get
      if(resource.exist?)
        res = resource.get(request, response)
        if(res == OK && !resource.collection?)
          response['Etag'] ||= resource.etag
          response['Content-Type'] ||= resource.content_type
          response['Content-Length'] ||= resource.content_length.to_s
          response['Last-Modified'] ||= resource.last_modified.httpdate
        end
        res
      else
        NotFound
      end
    end

    # Return response to PUT
    def put
      if(resource.collection?)
        Forbidden
      elsif(!resource.parent_exists? || !resource.parent_collection?)
        Conflict
      else
        resource.lock_check if resource.supports_locking?
        status = resource.put(request, response)
        response['Location'] = "#{scheme}://#{host}:#{port}#{resource.url_format}" if status == Created
        response.body = response['Location'] || ''
        status
      end
    end

    # Return response to POST
    def post
      resource.post(request, response)
    end

    # Return response to DELETE
    def delete
      if(resource.exist?)
        resource.lock_check if resource.supports_locking?
        resource.delete
      else
        NotFound
      end
    end

    # Return response to MKCOL
    def mkcol
      resource.lock_check if resource.supports_locking?
      status = resource.make_collection
      gen_url = "#{scheme}://#{host}:#{port}#{resource.url_format}" if status == Created
      if(resource.use_compat_mkcol_response?)
        multistatus do |xml|
          xml.response do
            xml.href gen_url
            xml.status "#{http_version} #{status.status_line}"
          end
        end
      else
        status
      end
    end

    # Return response to COPY
    def copy
      move(:copy)
    end

    # args:: Only argument used: :copy
    # Move Resource to new location. If :copy is provided,
    # Resource will be copied (implementation ease)
    def move(*args)
      unless(resource.exist?)
        NotFound
      else
        resource.lock_check if resource.supports_locking? && !args.include?(:copy)
        destination = url_unescape(env['HTTP_DESTINATION'].sub(%r{https?://([^/]+)}, ''))
        dest_host = $1
        if dest_host
          dest_host.sub!(/^.+@/, '')
          dest_host.sub!(/:\d{2,5}$/, '')
        end

        if(dest_host && dest_host != request.host)
          BadGateway
        elsif(destination == resource.public_path)
          Forbidden
        else
          dest = resource_class.new(destination, clean_path(destination), @request, @response, @options.merge(:user => resource.user))
          status = nil
          if(args.include?(:copy))
            return BadRequest unless depth.is_a?(Symbol) || depth == 0
            status = resource.copy(dest, overwrite, depth)
          else
            return BadRequest unless depth.is_a?(Symbol) || depth > 1
            status = resource.move(dest, overwrite)
          end

          status

        end
      end
    end

    # Return response to PROPFIND
    def propfind
      unless(resource.exist?)
        NotFound
      else
        if request_document.xpath("//#{ns}propfind").empty? or
          !request_document.xpath("//#{ns}propfind/#{ns}allprop").empty? or
          (request.content_length == '0') or
          (request.content_length.nil?)

          properties = resource.properties

        elsif !request_document.xpath("//#{ns}propfind/#{ns}propname").empty?

          multistatus = Ox::Element.new(D_MULTISTATUS)
          multistatus << Ox::Raw.new(resource.propnames_xml_with_depth(depth))
          render_ox_xml(multistatus)
          return MultiStatus

        else
          check = request_document.xpath("//#{ns}propfind")
          if(check && !check.empty?)
            properties = request_document.xpath(
              "//#{ns}propfind/#{ns}prop"
            ).children.find_all{ |item|
              item.element?
            }.map{ |item|
              # We should do this, but Nokogiri transforms prefix w/ null href into
              # something valid.  Oops.
              # TODO: Hacky grep fix that's horrible
              hsh = to_element_hash(item)
              if(hsh.namespace.nil? && !ns.empty?)
                raise BadRequest if request_document.to_s.scan(%r{<#{item.name}[^>]+xmlns=""}).empty?
              end
              hsh
            }.compact
          else
            raise BadRequest
          end
        end

        multistatus = Ox::Element.new(D_MULTISTATUS)

        properties = properties.empty? ? resource.properties : properties
        properties = properties.map{|property| {element: property}}
        properties = resource.propfind_add_additional_properties(properties)

        multistatus << Ox::Raw.new(resource.properties_xml_with_depth({:get => properties}, depth))

        render_ox_xml(multistatus)

        MultiStatus
      end
    end


    # Return response to PROPPATCH
    def proppatch
      unless(resource.exist?)
        NotFound
      else
        resource.lock_check if resource.supports_locking?
        properties = {}
        request_document.xpath("/#{ns}propertyupdate").children.each do |element|
          case element.name
          when 'set', 'remove'
            prp = element.children.detect{|e|e.name == 'prop'}
            if(prp)
              prp.children.each do |elm|
                next if elm.name == 'text'
                properties[element.name] ||= []
                properties[element.name] << {:element => to_element_hash(elm), :value => elm.text}
              end
            end
          end
        end

        multistatus = Ox::Element.new(D_MULTISTATUS)

        multistatus << Ox::Raw.new(resource.properties_xml_with_depth(properties, depth))

        render_ox_xml(multistatus)
        MultiStatus
      end
    end


    # Lock current resource
    # NOTE: This will pass an argument hash to Resource#lock and
    # wait for a success/failure response.
    def lock
      lockinfo = request_document.xpath("//#{ns}lockinfo")
      asked = {}
      asked[:timeout] = request.env['Timeout'].split(',').map{|x|x.strip} if request.env['Timeout']
      asked[:depth] = depth
      unless([0, :infinity].include?(asked[:depth]))
        BadRequest
      else
        asked[:scope] = lockinfo.xpath("//#{ns}lockscope").children.find_all{|n|n.element?}.map{|n|n.name}.first
        asked[:type] = lockinfo.xpath("#{ns}locktype").children.find_all{|n|n.element?}.map{|n|n.name}.first
        asked[:owner] = lockinfo.xpath("//#{ns}owner/#{ns}href").children.map{|n|n.text}.first

        begin
          lock_time, locktoken = resource.lock(asked)

          lockdiscovery = ox_element(
            D_LOCKDISCOVERY,
            ox_activelock(
              time: lock_time,
              token: locktoken,
              depth: asked[:depth].to_s,
              scope: asked[:scope],
              type: asked[:type],
              owner: asked[:owner]
            )
          )
          render_ox_xml(ox_element(D_PROP, lockdiscovery))

          response.headers['Lock-Token'] = "<#{locktoken}>"
          response.status = resource.exist? ? OK : Created
        rescue LockFailure => e
          multistatus do |xml|
            e.path_status.each_pair do |path, status|
              xml.response do
                xml.href path
                xml.status "#{http_version} #{status.status_line}"
              end
            end
          end
        end
      end
    end

    # Unlock current resource
    def unlock
      resource.unlock(lock_token)
    end

    # Perform authentication
    # NOTE: Authentication will only be performed if the Resource
    # has defined an #authenticate method
    def authenticate
      authed = true
      if(resource.respond_to?(:authenticate, true))
        authed = false
        uname = nil
        password = nil
        if(request.env['HTTP_AUTHORIZATION'])
          auth = Rack::Auth::Basic::Request.new(request.env)
          if(auth.basic? && auth.credentials)
            uname = auth.credentials[0]
            password = auth.credentials[1]
          end
        end
        authed = resource.send(:authenticate, uname, password)
      end
      raise Unauthorized unless authed
    end

    private

    # Request environment variables
    def env
      @request.env
    end

    # Current request scheme (http/https)
    def scheme
      request.scheme
    end

    # Request host
    def host
      request.host
    end

    # Request port
    def port
      request.port
    end

    # Class of the resource in use
    def resource_class
      @options[:resource_class]
    end

    # Root URI path for the resource
    def root_uri_path
      @options[:root_uri_path]
    end

    # Returns Resource path with root URI removed
    def implied_path
      clean_path(@request_path)
    end

    # x:: request path
    # Unescapes path and removes root URI if applicable
    def clean_path(x)
      ip = url_unescape(x)
      ip.sub!(/^#{Regexp.escape(root_uri_path)}/, '') if root_uri_path
      ip
    end

    # Unescaped request path
    def actual_path
      url_unescape(@request_path)
    end

    # Lock token if provided by client
    def lock_token
      env['HTTP_LOCK_TOKEN'] || nil
    end

    # Requested depth
    def depth
      d = env['HTTP_DEPTH']
      if(d =~ /^\d+$/)
        d = d.to_i
      else
        d = :infinity
      end
      d
    end

    # Overwrite is allowed
    def overwrite
      env['HTTP_OVERWRITE'].to_s.upcase != 'F'
    end

    # XML parsed request
    def request_document
      @request_document ||= Nokogiri.XML(request.body.read)
    rescue
      raise BadRequest
    end

    # Namespace being used within XML document
    def ns(wanted_uri=DAV_NAMESPACE)
      if request_document and
        request_document.root and
        ns_defs = request_document.root.namespace_definitions and
        ns_defs.size > 0

        result = ns_defs.detect{ |nd| nd.href == wanted_uri } || ns_defs.first
        result = result.prefix.nil? ? 'xmlns' : result.prefix.to_s
        result += ':' unless result.empty?
        result
      else
        ''
      end
    end

    # root_type:: Root tag name
    # Render XML and set Rack::Response#body= to final XML
    def render_xml(root_type)
      raise ArgumentError.new 'Expecting block' unless block_given?
      doc = Nokogiri::XML::Builder.new do |xml_base|
        xml_base.send(root_type.to_s, {DAV_XML_NS => DAV_NAMESPACE}.merge(resource.root_xml_attributes)) do
          xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
          xml = xml_base[DAV_NAMESPACE_NAME]
          yield xml
        end
      end

      if(@options[:pretty_xml])
        response.body = doc.to_xml
      else
        response.body = doc.to_xml(
          :save_with => Nokogiri::XML::Node::SaveOptions::AS_XML
        )
      end
      response['Content-Type'] = XML_CONTENT_TYPE
      response['Content-Length'] = response.body.size.to_s
    end

    def render_ox_xml(xml_body)
      resource.namespaces.each do |href, prefix|
        xml_body["xmlns:#{prefix}"] = href
      end

      xml_doc = Ox::Document.new(version: XML_VERSION)
      xml_doc << xml_body

      response.body = Ox.dump(xml_doc, {indent: -1, with_xml: true})

      response['Content-Type'] = XML_CONTENT_TYPE
      response['Content-Length'] = response.body.size.to_s
    end


    # block:: block
    # Creates a multistatus response using #render_xml and
    # returns the correct status
    def multistatus(&block)
      render_xml(:multistatus, &block)
      MultiStatus
    end

    # xml:: Nokogiri::XML::Builder
    # errors:: Array of errors
    # Crafts responses for errors
    def response_errors(xml, errors)
      for path, status in errors
        xml.response do
          xml.href "#{scheme}://#{host}:#{port}#{URI.escape(path)}"
          xml.status "#{http_version} #{status.status_line}"
        end
      end
    end

    # xml:: Nokogiri::XML::Builder
    # element:: Nokogiri::XML::Element
    # Converts element into proper text
    def xml_convert(xml, element)
      xml.doc.root.add_child(element)
    end

  end

end
