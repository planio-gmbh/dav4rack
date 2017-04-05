require 'bundler'
Bundler.setup

require 'rake/testtask'
require 'rspec/core/rake_task'

namespace :test do

  Rake::TestTask.new(:unit) do |t|
    t.libs << 'test'
    t.pattern = Dir.glob('test/unit/*_test.rb')
  end

  Rake::TestTask.new(:integration) do |t|
    t.libs << 'test'
    t.pattern = Dir.glob('test/integration/*_test.rb')
  end

  Rake::TestTask.new(:performance) do |t|
    t.libs << 'test'
    t.pattern = Dir.glob('test/performance/*_test.rb')
  end

end

task default: ['test:unit', 'test:integration']
