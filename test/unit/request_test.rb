require 'test_helper'
require 'dav4rack/request'

class RequestTest < Minitest::Test


  def request(env = {}, options = {})
    env = {
      'HTTP_HOST' => 'localhost',
      'REMOTE_USER' => 'user'
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

  def test_should_handle_script_name
    r = request('PATH_INFO' => '/fo%20o/a', 'SCRIPT_NAME' => '/redmine')
    assert_equal '/redmine/fo o/a', r.unescaped_path
    assert_equal '/fo o/a', r.unescaped_path_info
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



end
