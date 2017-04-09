require 'test_helper'

require 'dav4rack/resources/file_resource'

require_relative 'generic_resource_tests'

class FileResourceTest < DAV4RackIntegrationTest
  include GenericResourceTests

  def setup
    super
    @handler = DAV4Rack::Handler.new(root: DOC_ROOT,
                                     resource_class: ::DAV4Rack::FileResource)
  end

  def test_should_set_prop_without_namespace
    xml = <<-XML
<?xml version="1.0" encoding="utf-8" ?>
<propertyupdate xmlns="DAV:"><set><prop><nonamespace xmlns="">randomvalue</nonamespace></prop></set></propertyupdate>
    XML

    proppatch '/', input: xml
    assert_response 207

    assert response = response_xml.xpath('//d:multistatus/d:response').first
    assert propstat = response.xpath('//d:propstat').first
    assert propstat.xpath('//d:prop/nonamespace').first
    assert_match(/200 OK/, propstat.xpath('//d:status').first.text)


    propfind '/',  env: {'HTTP_DEPTH' => '0'}, input: <<-PROPFIND
<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:"><prop>
<nonamespace xmlns=""/>
</prop></propfind>
    PROPFIND

    assert_response 207

    assert response = response_xml.xpath('//d:multistatus/d:response').first
    assert propstat = response.xpath('//d:propstat').first
    assert_equal 'randomvalue', propstat.xpath('//d:prop/nonamespace').text
    assert_match(/200 OK/, propstat.xpath('//d:status').first.text)

  end

end


