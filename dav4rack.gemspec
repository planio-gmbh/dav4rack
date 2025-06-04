$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'

require 'dav4rack/version'

Gem::Specification.new do |s|
  s.name = 'dav4rack'
  s.version = DAV4Rack::VERSION
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/chrisroberts/dav4rack'
  s.description = 'WebDAV handler for Rack'
  s.require_path = 'lib'
  s.executables << 'dav4rack'
  s.add_dependency 'nokogiri', '~> 1.6'
  s.add_dependency 'uuidtools', '~> 2.1'
  s.add_dependency 'rack', '~> 3.1'
  s.add_dependency 'ox', '~> 2.1'
  s.add_dependency 'addressable', '~> 2.5'
  s.required_ruby_version = '~> 3.0'
  s.files = Dir["{lib}/**/*.rb", "bin/*", "LICENSE", "*.md", "*.rdoc"]
end
