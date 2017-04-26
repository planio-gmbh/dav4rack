module GenericResourceTests


  def test_should_return_all_options
    options '/'
    assert_response :ok

    DAV4RackIntegrationTest::METHODS.each do |method|
      assert @response['allow'].include?(method), "headers did not include #{method}"
    end

    assert_equal '1', @response.headers['Dav']
  end



  def test_should_propfind_with_depth_zero
    propfind '/',  env: {'HTTP_DEPTH' => '0'}, input: <<-PROPFIND
<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:"><prop>
<getcontentlength xmlns="DAV:"/>
<getlastmodified xmlns="DAV:"/>
<displayname xmlns="DAV:"/>
<resourcetype xmlns="DAV:"/>
<foo xmlns="http://example.com/neon/litmus/"/>
<bar xmlns="http://example.com/neon/litmus/"/>
</prop></propfind>
    PROPFIND
    assert_response :multi_status

    response = response_xml.xpath("//d:response")
    assert_equal 1, response.size
    response = response.first
    assert_equal 2, response.xpath("//d:propstat").size
    assert response.xpath("//d:propstat/d:status").detect{|e|e.text =~ /200/}
    assert response.xpath("//d:propstat/d:status").detect{|e|e.text =~ /404/}
  end

  def test_should_return_headers
    put '/test.html', input: '<html/>'
    assert_response :created

    head '/test.html'
    assert_response :ok

    assert @response.headers['etag']
    assert_match(/html/, @response.headers['content-type'])
    assert @response.headers['last-modified']
  end

  def test_should_not_find_a_nonexistent_resource
    get '/not_found'
    assert_response :not_found
  end

  def test_should_translate_directory_traversal_to_an_absolute_path
    put '/test', input: 'body'
    assert_response :created

    get '/../../../test'
    assert_response :ok
    assert_equal 'body', @response.body
  end

  def test_should_create_a_resource_and_allow_its_retrieval
    put '/test.txt', input: 'body'
    assert_response :created

    get '/test.txt'
    assert_response :ok
    assert_equal 'body', @response.body
  end


  def test_should_return_an_absolute_url_after_a_put_request
    put '/test', :input => 'body'
    assert_response :created
    assert_match(/http:\/\/localhost(:\d+)?\/test/, @response['Location'])
  end

  def test_should_create_and_find_a_url_with_escaped_characters
    put '/a b', input: 'body'
    assert_response :created

    get '/a b'
    assert_response :ok
    assert_equal 'body', @response.body
  end

  def test_should_delete_a_single_resource
    put '/test', input: 'body'
    assert_response :created
    delete '/test'
    assert_response :no_content
  end

  def test_should_delete_recursively
    mkcol('/folder')
    assert_response :created
    put('/folder/a', :input => 'body')
    assert_response :created
    put('/folder/b', :input => 'body')
    assert_response :created

    delete('/folder')
    assert_response :no_content
    get('/folder')
    assert_response :not_found
    get('/folder/a')
    assert_response :not_found
    get('/folder/b')
    assert_response :not_found
  end

  def test_should_not_allow_copy_to_another_domain
    put('/test', :input => 'body')
    assert_response :created
    copy('/test', env: {'HTTP_DESTINATION' => 'http://another/test'})
    assert_response :bad_gateway
  end

  def test_should_not_allow_copy_to_the_same_resource
    put('/test', :input => 'body')
    assert_response :created
    copy('/test', env: { 'HTTP_DESTINATION' => '/test' })
    assert_response :forbidden
  end

  def test_should_copy_a_single_resource
    put '/test', input: 'body'
    assert_response :created
    copy '/test', env: { 'HTTP_DESTINATION' => '/copy' }
    assert_response :created
    get '/copy'
    assert_response :ok
    assert_equal 'body', @response.body
  end

  def test_should_copy_a_resource_with_escaped_characters
    put '/a b', input: 'body'
    assert_response :created
    copy('/a b', env: { 'HTTP_DESTINATION' => url_escape('/a c') })
    assert_response :created
    get '/a c'
    assert_response :ok
    assert_equal 'body', @response.body
  end

  def test_should_deny_a_copy_without_overwrite
    put('/test', :input => 'body')
    assert_response :created
    put('/copy', :input => 'copy')
    assert_response :created
    copy('/test', env: { 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'F'})
    assert_response :precondition_failed
    get('/copy')
    assert_equal 'copy', @response.body
  end

  def test_should_allow_a_copy_with_overwrite
    put('/test', :input => 'body')
    assert_response :created
    put('/copy', :input => 'copy')
    assert_response :created
    copy('/test', env: { 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'T'})
    assert_response :no_content
    get('/copy')
    assert_equal 'body', @response.body
  end

  def test_should_copy_a_collection
    mkcol('/folder')
    assert_response :created
    copy('/folder', env: { 'HTTP_DESTINATION' => '/copy' })
    assert_response :created
    propfind('/copy', input: propfind_xml(:resourcetype))
    refute multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').empty?
  end

  def test_should_copy_a_collection_resursively
    mkcol('/folder')
    assert_response :created
    put('/folder/a', :input => 'A')
    assert_response :created
    put('/folder/b', :input => 'B')
    assert_response :created

    copy('/folder', env: { 'HTTP_DESTINATION' => '/copy' })
    assert_response :created
    propfind('/copy', :input => propfind_xml(:resourcetype))
    refute multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').empty?
    get('/copy/a')
    assert_equal 'A', @response.body
    get('/copy/b')
    assert_equal 'B', @response.body
  end

  def test_should_move_a_collection_recursively
    mkcol('/folder')
    assert_response :created
    put('/folder/a', :input => 'A')
    assert_response :created
    put('/folder/b', :input => 'B')
    assert_response :created

    move('/folder', env: {'HTTP_DESTINATION' => '/move'})
    assert_response :created
    propfind('/move', input: propfind_xml(:resourcetype))
    refute multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').empty?

    get('/move/a')
    assert_equal 'A', @response.body
    get('/move/b')
    assert_equal 'B', @response.body
    get('/folder/a')
    assert_response :not_found
    get('/folder/b')
    assert_response :not_found
  end

  def test_should_create_a_collection
    mkcol('/folder')
    assert_response :created
    propfind('/folder', :input => propfind_xml(:resourcetype))
    refute multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').empty?
  end

  def test_should_return_full_urls_after_creating_a_collection
    mkcol('/folder')
    assert_response :created
    propfind('/folder', :input => propfind_xml(:resourcetype))
    refute multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').empty?
    assert_match(/http:\/\/localhost(:\d+)?\/folder/, multistatus_response('/d:href').first.text)
  end

  def test_should_not_find_properties_for_nonexistent_resources
    propfind('/non')
    assert_response :not_found
  end

  def test_should_find_all_properties
    xml = render(:propfind) { |x| x.allprop }

    propfind '/', input: xml

    assert_match(/http:\/\/localhost(:\d+)?\//,
                 multistatus_response('/d:href').first.text.strip)

    %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength).each do |prop|
      refute multistatus_response("/d:propstat/d:prop/d:#{prop}").empty?
    end
  end

  def test_should_find_propnames
    xml = render(:propfind) { |x| x.propname }

    propfind '/', input: xml

    assert_match(/http:\/\/localhost(:\d+)?\//,
                 multistatus_response('/d:href').first.text.strip)

    %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength).each do |prop|
      prop_xml = multistatus_response("/d:propstat/d:prop/d:#{prop}").first
      assert prop_xml.text.empty?, "expected #{prop_xml} to be empty"
    end
  end

  def test_should_find_named_properties
    put '/test.html', input: '<html/>'
    assert_response :created

    propfind '/test.html',
             input: propfind_xml(:getcontenttype, :getcontentlength)

    assert_equal 'text/html',
      multistatus_response('/d:propstat/d:prop/d:getcontenttype').first.text
    assert_equal '7',
      multistatus_response('/d:propstat/d:prop/d:getcontentlength').first.text
  end

  def test_should_lock_a_resource
    put '/test', input: 'body'
    assert_response :created

    xml = render(:lockinfo) do |x|
      x.lockscope { x.exclusive }
      x.locktype { x.write }
      x.owner { x.href "http://test.de/" }
    end

    lock '/test', input: xml
    assert_response :ok

    match = ->(pattern){
      response_xml.xpath "/d:prop/d:lockdiscovery/d:activelock#{pattern}"
    }

    refute match[''].empty?
    refute match['/d:locktype'].empty?
    refute match['/d:lockscope'].empty?
    refute match['/d:depth'].empty?
    refute match['/d:timeout'].empty?
    refute match['/d:locktoken'].empty?
    refute match['/d:owner'].empty?
  end


  def test_should_return_correct_urls_when_not_mapped_to_root
    put('/test', input: 'body', env: { 'SCRIPT_NAME' => '/webdav' })
    assert_response :created
    assert @response.headers['Location'].end_with? '/webdav/test'
  end



end
