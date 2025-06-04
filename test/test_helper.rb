require 'minitest/autorun'
require 'rack/mock'
require 'byebug'

require 'dav4rack'
require 'nokogiri'
require 'addressable/uri'

class DAV4RackTest < Minitest::Test

  def env_for(method, path, env = {})
    Rack::MockRequest.env_for(path, env.merge(method: method))
  end
end

class DAV4RackIntegrationTest < DAV4RackTest

  DOC_ROOT = File.expand_path(File.dirname(__FILE__) + '/htdocs')

  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)

  def setup
    FileUtils.mkdir_p(DOC_ROOT)
  end

  def teardown
    FileUtils.rm_rf(DOC_ROOT)
  end

  private

  METHODS.each do |method|
    define_method(method.downcase) do |*args, **kwargs|
      request(method, *args, **kwargs)
    end
  end

  def request(method, path = '/', input: nil, env: {}, options: {})
    if input
      input = StringIO.new input if input.is_a? String
      env[Rack::RACK_INPUT] = input
      env['CONTENT_LENGTH'] = input.size.to_s
    end

    if defined? @handler
      r = Rack::MockRequest.new(@handler)
      path = Addressable::URI.encode_component path
      @response = r.request(method, path, env)
    else
      env = env_for method, path, env

      @options ||= {
        root: DOC_ROOT,
        resource_class: DAV4Rack::FileResource
      }
      @options.update options
      @request = DAV4Rack::Request.new env, @options
      @response = Rack::Response.new
      @controller = DAV4Rack::Controller.new @request, @response, @options
      @controller.process
      @response = Rack::MockResponse.new @response.status, @response.headers, @response.body

    end

  end

  def url_escape(s)
    Addressable::URI.encode s
  end

  def response_xml
    Nokogiri.XML(@response.body){|config| config.strict}
  end

  def propfind_xml(*props)
    render(:propfind) do |xml|
      xml.prop do
        props.each do |prop|
        xml.send(prop.to_sym)
        end
      end
    end
  end

  def render(root_type)
    raise ArgumentError.new 'Expecting block' unless block_given?
    doc = Nokogiri::XML::Builder.new do |xml_base|
      xml_base.send(root_type.to_s, 'xmlns:D' => 'DAV:') do
        xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
        xml = xml_base['D']
        yield xml
      end
    end
    doc.to_xml
  end

  STATUS_SYMBOLS = Hash[
    DAV4Rack::HTTPStatus::StatusMessage.map do |code, name|
      [name.gsub(/[ \-]/,'_').downcase.to_sym, code]
    end
  ]
  def assert_response(status)
    if status.is_a? Symbol
      status = STATUS_SYMBOLS[status]
    end
    assert_equal status, @response.status
  end


  def multistatus_response(pattern)
    assert_response :multi_status
    refute response_xml.xpath('//d:multistatus/d:response', response_xml.root.namespaces).empty?
    response_xml.xpath("//d:multistatus/d:response#{pattern}", response_xml.root.namespaces)
  end

  def multi_status_created
    refute response_xml.xpath('//d:multistatus/d:response/d:status').empty?
    assert_match(/Created/, response_xml.xpath('//d:multistatus/d:response/d:status').text)
  end

  def multi_status_ok
    refute response_xml.xpath('//d:multistatus/d:response/d:status').empty?
    assert_match(/OK/, response_xml.xpath('//d:multistatus/d:response/d:status').text)
  end

  def multi_status_no_content
    refute response_xml.xpath('//d:multistatus/d:response/d:status').empty?
    assert_match(/No Content/, response_xml.xpath('//d:multistatus/d:response/d:status').text)

  end


end
