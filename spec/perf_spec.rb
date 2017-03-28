require_relative 'spec_helper'

describe DAV4Rack::Handler do
  DOC_ROOT = File.expand_path(File.dirname(__FILE__) + '/htdocs')
  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)

  before do
    FileUtils.mkdir(DOC_ROOT) unless File.exists?(DOC_ROOT)
    @controller = DAV4Rack::Handler.new(:root => DOC_ROOT)
  end

  after do
    FileUtils.rm_rf(DOC_ROOT) if File.exists?(DOC_ROOT)
  end

  attr_reader :response

  def request(method, uri, options={})
    options = {
      'HTTP_HOST' => 'localhost',
      'REMOTE_USER' => 'user'
    }.merge(options)
    request = Rack::MockRequest.new(@controller)
    @response = request.request(method, uri, options)
  end

  METHODS.each do |method|
    define_method(method.downcase) do |*args|
      request(method, *args)
    end
  end

  def render(root_type)
    raise ArgumentError.new 'Expecting block' unless block_given?
    doc = Nokogiri::XML::Builder.new do |xml_base|
      xml_base.send(root_type.to_s, 'xmlns:D' => 'D:') do
        xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
        xml = xml_base['D']
        yield xml
      end
    end
    doc.to_xml
  end

  def url_escape(string)
    URI.escape(string)
  end

  def response_xml
    Nokogiri.XML(@response.body)
  end

  def multistatus_response(pattern)
    @response.should be_multi_status
    response_xml.xpath('//D:multistatus/D:response', response_xml.root.namespaces).should_not be_empty
    response_xml.xpath("//D:multistatus/D:response#{pattern}", response_xml.root.namespaces)
  end

  def multi_status_created
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /Created/
  end

  def multi_status_ok
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /OK/
  end

  def multi_status_no_content
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /No Content/
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

  it 'should fucking perform' do
    require 'ox'
    require 'benchmark'

    # binding.pry

    # doc = Ox::Document.new(:version => '1.0')

    # top = Ox::Element.new('D:top')
    # top[:name] = 'sample'
    # doc << top

    # mid = Ox::Element.new('D:middle')
    # mid[:name] = 'second'
    # top << mid

    # bot = Ox::Element.new('D:bottom')
    # bot[:name] = 'third'
    # mid << bot

    # xml = Ox.dump(doc, {with_xml: true, indent: -1})
    # print Ox.dump(doc, {with_xml: true, indent: 2})

    xml = render(:propfind) do |xml|
      xml.allprop
    end

    1000.times do |index|
      FileUtils.mkdir(File.join(DOC_ROOT, "dir_#{index}"))
    end

    require 'ruby-prof'
    RubyProf.start
    propfind('http://localhost/', :input => xml)
    result = RubyProf.stop
    open("callgrind.html", "w") do |f|
      # RubyProf::GraphPrinter.new(result).print(f, {})
      # RubyProf::CallTreePrinter.new(result).print(f, :min_percent => 1)
      RubyProf::GraphHtmlPrinter.new(result).print(f, {})
    end

    # without ox 9.080960035324097
    # with ox 6.845001220703125
    # second pass with ox 4.0348320007
    b = Benchmark.measure do
      10.times do
        propfind('http://localhost/', :input => xml)
      end
    end

    b.real.should == 1


    multistatus_response('/D:href').first.text.strip.should =~ /http:\/\/localhost(:\d+)?\//

    props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    props.each do |prop|
      multistatus_response("/D:propstat/D:prop/D:#{prop}").should_not be_empty
    end
  end
end
