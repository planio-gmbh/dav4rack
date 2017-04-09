# frozen_string_literal: true

require 'addressable/uri'
require 'dav4rack/logger'

module DAV4Rack
  class Request < Rack::Request

    # Root URI path for the resource
    attr_reader :root_uri_path

    # options:
    #   root_uri_path: mount point of the handler, either absolute or relative
    #   to env['SCRIPT_NAME']. Must be blank or start with a forward slash.
    def initialize(env, options)
      super env

      sanitize_path_info

      self.root_uri_path = options[:root_uri_path]
    end


    def authorization?
      !!env['HTTP_AUTHORIZATION']
    end

    # path relative to root uri
    def relative_path
      @relative_path ||= unescaped_path.slice(@root_uri_path.length,
                                              unescaped_path.length)
    end

    # the full path (script_name aka rack mount point + path_info)
    def unescaped_path
      @unescaped_path ||= self.class.unescape_path path
    end

    def self.unescape_path(p)
      p = p.dup
      p.force_encoding 'UTF-8'
      Addressable::URI.unencode p
    end


    # Namespace being used within XML document
    def ns(wanted_uri = XmlElements::DAV_NAMESPACE)
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



    # Lock token if provided by client
    def lock_token
      get_header 'HTTP_LOCK_TOKEN'
    end


    # Requested depth
    def depth
      @http_depth ||= begin
        if d = get_header('HTTP_DEPTH') and (d == '0' or d == '1')
          d.to_i
        else
          :infinity
        end
      end
    end


    # Destination header
    def destination
      @destination ||= if h = get_header('HTTP_DESTINATION')
        DestinationHeader.new(
          h, script_name: root_uri_path
        )
      end
    end


    # Overwrite is allowed
    def overwrite?
      get_header('HTTP_OVERWRITE').to_s.upcase != 'F'
    end


    # parsed XML request body if any (Nokogiri XML doc)
    def request_document
      @request_document ||= parse_request_body
    end
    alias document request_document

    def url_for(path)
      "#{scheme}://#{host}:#{port}#{path}"
    end


    REDIRECTABLE_CLIENTS = [
      /cyberduck/i,
      /konqueror/i
    ]

    # Does client allow GET redirection
    # TODO: Get a comprehensive list in here.
    # TODO: Allow this to be dynamic so users can add regexes to match if they know of a client
    # that can be supported that is not listed.
    def client_allows_redirect?
      ua = self.user_agent
      REDIRECTABLE_CLIENTS.any? { |re| ua =~ re }
    end


    MS_CLIENTS = [
      /microsoft-webdav/i,
      /microsoft office/i
    ]

    # Basic user agent testing for MS authored client
    def is_ms_client?
      ua = self.user_agent
      MS_CLIENTS.any? { |re| ua =~ re }
    end

    def get_header(name)
      @env[name]
    end

    private

    def root_uri_path=(p)
      if p
        @root_uri_path = p.chomp '/'
        unless @root_uri_path.start_with? script_name
          @root_uri_path.prepend script_name.chomp('/')
        end
      else
        @root_uri_path = script_name.chomp('/')
      end
    end

    def sanitize_path_info
      # expand '..' but preserve trailing slash
      collection = path_info.end_with? '/'
      self.path_info = ::File.expand_path(path_info)
      self.path_info.force_encoding 'UTF-8'
      self.path_info << '/' if collection and !path_info.end_with?('/')
    end

    def parse_request_body
      return Nokogiri.XML(body.read){ |config|
        config.strict
      } if body
    rescue
      DAV4Rack::Logger.error $!.message
      raise ::DAV4Rack::HTTPStatus::BadRequest
    end

  end
end
