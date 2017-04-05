require 'test_helper'

class HandlerTest < DAV4RackTest

  class DummyController < Struct.new(:request, :response, :options)
    include DAV4Rack::HTTPStatus

    def authenticate
    end

    def process
      response.body = request.request_method
      OK
    end
  end

  def setup
    super
    @handler = DAV4Rack::Handler.new(controller_class: DummyController)
  end

  def test_should_instantiate_controller_and_call_corresponding_method
    status, headers, body = @handler.call env_for(:get, '/')
    assert_equal 'GET', body.body.join
    assert_equal '3', headers['Content-Length']
    assert_equal 200, status
  end



end

