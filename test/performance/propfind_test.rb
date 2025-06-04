require 'test_helper'
require 'ruby-prof'
require 'benchmark'

class PropfindTest < DAV4RackIntegrationTest

  def setup
    @handler = DAV4Rack::Handler.new

    @xml = render(:propfind) {|x| x.allprop }

    1000.times do |index|
      FileUtils.mkdir_p(File.join(DOC_ROOT, "dir_#{index}"))
    end
  end


  def test_profile
    skip unless ENV['PROFILE']

    RubyProf.start
    propfind '/', input: @xml
    result = RubyProf.stop
    open("callgrind.html", "w") do |f|
      # RubyProf::GraphPrinter.new(result).print(f, {})
      # RubyProf::CallTreePrinter.new(result).print(f, :min_percent => 1)
      RubyProf::GraphHtmlPrinter.new(result).print(f, {})
    end
  end


  def test_propfind_should_be_fast
    # without ox 9.080960035324097
    # with ox 6.845001220703125
    # second pass with ox 4.0348320007
    b = Benchmark.measure do
      10.times do
        propfind '/', input: @xml
      end
    end

    assert b.real <= 3.0, "time taken should be less than 3 seconds, was: #{b.real}"

    assert_match(/http:\/\/example.org(:\d+)?\//, multistatus_response('/d:href').first.text.strip)
    props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    props.each do |prop|
      refute multistatus_response("/d:propstat/d:prop/d:#{prop}").empty?
    end

  end

end
