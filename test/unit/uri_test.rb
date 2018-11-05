require 'test_helper'
require 'dav4rack/uri'

class UriTest < Minitest::Test

  def test_should_parse_header_value_with_root_set
    d = DAV4Rack::Uri.new 'https://example.com/foo/bar', script_name: '/foo'
    assert_equal 'example.com', d.host
    assert_equal '/foo/bar', d.path
    assert_equal '/bar', d.path_info
  end

  def test_should_parse_and_unescape_header_value
    d = DAV4Rack::Uri.new 'https://example.com/fo%20o/bar'
    assert_equal 'example.com', d.host
    assert_equal '/fo o/bar', d.path
    assert_equal '/fo o/bar', d.path_info
  end

  def test_should_handle_wrong_script_name
    d = DAV4Rack::Uri.new 'https://example.com/foo/bar', script_name: '/other'
    assert_equal 'example.com', d.host
    assert_equal '/foo/bar', d.path
    assert_nil d.path_info
  end

  def test_should_parse_path
    d = DAV4Rack::Uri.new '/foo/bar', script_name: '/other'
    assert_nil d.host
    assert_equal '/foo/bar', d.path
    assert_nil d.path_info

    d = DAV4Rack::Uri.new '//foo/bar', script_name: '/foo'
    assert_nil d.host
    assert_equal '/foo/bar', d.path
    assert_equal '/bar', d.path_info
  end
end
