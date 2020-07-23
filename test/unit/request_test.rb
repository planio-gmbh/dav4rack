require 'test_helper'
require 'dav4rack/request'

class RequestTest < Minitest::Test


  def request(env = {}, options = {})
    env = {
      'HTTP_HOST' => 'localhost',
      'REMOTE_USER' => 'user',
      'rack.url_scheme' => 'https',
      'SERVER_PORT' => 443,
    }.merge(env)
    DAV4Rack::Request.new(env, options)
  end

  def test_should_have_unescaped_path
    assert_equal '/fo o/a', request('PATH_INFO' => '/fo%20o/a').unescaped_path
    assert_equal '/fo o/a', request('PATH_INFO' => '/fo%20o/a').unescaped_path_info
    assert_equal '/fo o/a/', request('PATH_INFO' => '/fo%20o/a/').unescaped_path_info
  end

  def test_should_expand_pathinfo
    assert_equal '/a', request('PATH_INFO' => '/foo/../a').unescaped_path
    assert_equal '/a', request('PATH_INFO' => '/foo/../a').unescaped_path_info

    r = request('PATH_INFO' => '/foo/../../../a', 'SCRIPT_NAME' => '/redmine')
    assert_equal '/redmine/a', r.unescaped_path
    assert_equal '/a', r.unescaped_path_info
  end

  def test_should_expand_path_with_unescaped_special_chars
    assert_equal '/a [foo].pdf', request('PATH_INFO' => '/foo/../a%20[foo].pdf').unescaped_path
    assert_equal '/a f#o.pdf', request('PATH_INFO' => '/foo/../a%20f#o.pdf').unescaped_path
  end

  def test_should_normalize_path_with_double_slashes
    assert_equal '/foo', request('PATH_INFO' => '/').expand_path('//foo')
    assert_equal '/foo/', request('PATH_INFO' => '/').expand_path('//foo/')
    assert_equal '/foo/a', request('PATH_INFO' => '/').expand_path('//foo/a')
  end

  def test_should_not_change_chars
    assert_equal "/TMD7DU0-I17U-RISK-2ºSEMESTRE 2017.xlsx", request('PATH_INFO' => '/TMD7DU0-I17U-RISK-2%C2%BASEMESTRE%202017.xlsx').unescaped_path
  end

  def test_should_handle_script_name
    r = request('PATH_INFO' => '/fo%20o/a', 'SCRIPT_NAME' => '/redmine')
    assert_equal '/redmine/fo o/a', r.unescaped_path
    assert_equal '/fo o/a', r.unescaped_path_info

    assert_equal "/foo bar", r.path_info_for("/redmine/foo%20bar")
    assert_nil r.path_info_for("/redmine/foo%20bar", script_name: '/other')
    assert_equal "/foo bar", r.path_info_for("/other/foo%20bar", script_name: '/other')
  end

  def test_should_parse_depth_header
    {
      infinity: [nil, 'foo', '', 'infinity', '2'],
      1 => ['1'],
      0 => ['0']
    }.each do |expected, values|
      values.each do |value|
        assert_equal expected, request('HTTP_DEPTH' => value).depth, "#{value} should result in #{expected}"
      end
    end
  end

  def test_should_generate_path
    r = request('PATH_INFO' => '/', 'SCRIPT_NAME' => '/redmine')
    assert_equal '/redmine/fo%20o%5B%23.pdf',
      r.path_for('/fo o[#.pdf')
  end

  def test_should_generate_url
    r = request('PATH_INFO' => '/', 'SCRIPT_NAME' => '/redmine')
    assert_equal 'https://localhost:443/redmine/fo%20o%5B%23.pdf',
      r.url_for('/fo o[#.pdf')
  end


end
