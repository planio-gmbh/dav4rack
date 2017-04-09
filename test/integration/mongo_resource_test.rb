require 'test_helper'

require 'mongo'
require 'dav4rack/resources/mongo_resource'

require_relative 'generic_resource_tests'

class MongoResourceTest < DAV4RackIntegrationTest
  include GenericResourceTests

  Mongo::Logger.logger.level = ::Logger::INFO

  def setup
    super
    DAV4Rack::MongoResource.database ||= Mongo::Client.new(
      [ '127.0.0.1:27017' ], database: 'dav4racktest'
    )
    @handler = DAV4Rack::Handler.new(resource_class: ::DAV4Rack::MongoResource)
  end

  def teardown
    DAV4Rack::MongoResource.database['fs.files'].delete_many
  end

end

