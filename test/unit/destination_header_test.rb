require 'test_helper'
require 'dav4rack/destination_header'
require 'dav4rack/uri'

class DestinationHeaderTest < Minitest::Test

  def test_should_parse_header_value_with_root_set
    d = DAV4Rack::DestinationHeader.new DAV4Rack::Uri.new('https://example.com/foo/bar', script_name: '/foo')
    assert_equal 'example.com', d.host
    assert_equal '/foo/bar', d.path
    assert_equal '/bar', d.path_info
  end

  def test_should_parse_and_unescape_header_value
    d = DAV4Rack::DestinationHeader.new DAV4Rack::Uri.new('https://example.com/fo%20o/bar')
    assert_equal 'example.com', d.host
    assert_equal '/fo o/bar', d.path
    assert_equal '/fo o/bar', d.path_info
  end

  def test_should_validate_uri_header
    d = DAV4Rack::DestinationHeader.new DAV4Rack::Uri.new('https://example.com/foo/bar')

    assert_nil d.validate host: 'example.com', resource_path: '/test'
    assert_equal DAV4Rack::HTTPStatus::BadGateway,
      d.validate(host: 'another.com', resource_path: '/test')
    assert_equal DAV4Rack::HTTPStatus::Forbidden,
      d.validate(host: 'example.com', resource_path: '/foo/bar')
  end

  def test_should_validate_path_header
    d = DAV4Rack::DestinationHeader.new DAV4Rack::Uri.new('/foo/bar')

    assert_nil d.validate host: 'example.com', resource_path: '/test'
    assert_nil d.validate(host: 'another.com', resource_path: '/test')
    assert_equal DAV4Rack::HTTPStatus::Forbidden,
      d.validate(host: 'example.com', resource_path: '/foo/bar')
  end

  def test_should_validate_path_with_script_name
    d = DAV4Rack::DestinationHeader.new DAV4Rack::Uri.new('/foo/bar', script_name: '/foo')
    assert_equal DAV4Rack::HTTPStatus::Forbidden,
      d.validate(host: 'example.com', resource_path: '/bar')
  end

end
