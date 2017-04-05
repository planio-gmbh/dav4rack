# frozen_string_literal: true

require 'dav4rack/logger'

module DAV4Rack
  class Handler
    include DAV4Rack::HTTPStatus

    def initialize(options={})
      @options = options.dup

      unless(@options[:resource_class])
        require 'dav4rack/resources/file_resource'
        @options[:resource_class] = FileResource
        @options[:root] ||= Dir.pwd
      end

      Logger.set(*@options[:log_to])
    end

    def call(env)
      start = Time.now
      request = setup_request env
      response = Rack::Response.new

      Logger.info "Processing WebDAV request: #{request.path} (for #{request.ip} at #{Time.now}) [#{request.request_method}]"

      controller = setup_controller request, response
      controller.process
      postprocess_response response

      # Apache wants the body dealt with, so just read it and junk it
      buf = true
      buf = request.body.read(8192) while buf

      if Logger.debug? and response.body.is_a?(String)
        Logger.debug "Response String:\n#{response.body}"
      end
      Logger.info "Completed in: #{((Time.now.to_f - start.to_f) * 1000).to_i} ms | #{response.status} [#{request.url}]"


      if response.body.is_a?(Rack::File)
        response.body.call env
      else
        response.finish
      end

    rescue Exception => e
      Logger.error "WebDAV Error: #{e}\n#{e.backtrace.join("\n")}"
      raise e
    end


    private


    def postprocess_response(response)
      if response.body.is_a?(String)
        response['Content-Length'] ||= response.body.length.to_s
      end
      response.body = [response.body] unless response.body.respond_to?(:each)
    end


    def setup_request(env)
      ::DAV4Rack::Request.new env, @options
    end


    def setup_controller(request, response)
      controller_class = @options[:controller_class] || ::DAV4Rack::Controller
      controller_class.new(request, response, @options)
    end

  end

end
