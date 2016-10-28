require 'uuidtools'
require 'dav4rack/http_status'
require 'dav4rack/lock_store'

module DAV4Rack

  class LockFailure < RuntimeError
    attr_reader :path_status
    def initialize(*args)
      super(*args)
      @path_status = {}
    end

    def add_failure(path, status)
      @path_status[path] = status
    end
  end

  class Resource
    include DAV4Rack::Utils

    DAV_NAMESPACE = 'DAV:'
    DAV_NAMESPACE_NAME = 'D'

    attr_reader :path, :options, :public_path, :request,
      :response, :propstat_relative_path, :root_xml_attributes, :namespaces
    attr_accessor :user
    @@blocks = {}

    class << self

      # This lets us define a bunch of before and after blocks that are
      # either called before all methods on the resource, or only specific
      # methods on the resource
      def method_missing(*args, &block)
        class_sym = self.name.to_sym
        @@blocks[class_sym] ||= {:before => {}, :after => {}}
        m = args.shift
        parts = m.to_s.split('_')
        type = parts.shift.to_s.to_sym
        method = parts.empty? ? nil : parts.join('_').to_sym
        if(@@blocks[class_sym][type] && block_given?)
          if(method)
            @@blocks[class_sym][type][method] ||= []
            @@blocks[class_sym][type][method] << block
          else
            @@blocks[class_sym][type][:'__all__'] ||= []
            @@blocks[class_sym][type][:'__all__'] << block
          end
        else
          raise NoMethodError.new("Undefined method #{m} for class #{self}")
        end
      end

    end

    include DAV4Rack::HTTPStatus

    # public_path:: Path received via request
    # path:: Internal resource path (Only different from public path when using root_uri's for webdav)
    # request:: Rack::Request
    # options:: Any options provided for this resource
    # Creates a new instance of the resource.
    # NOTE: path and public_path will only differ if the root_uri has been set for the resource. The
    #       controller will strip out the starting path so the resource can easily determine what
    #       it is working on. For example:
    #       request -> /my/webdav/directory/actual/path
    #       public_path -> /my/webdav/directory/actual/path
    #       path -> /actual/path
    # NOTE: Customized Resources should not use initialize for setup. Instead
    #       use the #setup method
    def initialize(public_path, path, request, response, options)
      @public_path = public_path
      @path = path
      @propstat_relative_path = !!options.delete(:propstat_relative_path)
      @root_xml_attributes = options.delete(:root_xml_attributes) || {}
      @namespaces = (options[:namespaces] || {}).merge({DAV_NAMESPACE => DAV_NAMESPACE_NAME})
      @request = request
      @response = response
      unless(options.has_key?(:lock_class))
        @lock_class = LockStore
      else
        @lock_class = options[:lock_class]
        raise NameError.new("Unknown lock type constant provided: #{@lock_class}") unless @lock_class.nil? || defined?(@lock_class)
      end
      @options = options
      @max_timeout = options[:max_timeout] || 86400
      @default_timeout = options[:default_timeout] || 60
      @user = @options[:user] || request.ip
      setup if respond_to?(:setup)
    end

    # Returns if resource supports locking
    def supports_locking?
      false #true
    end

    # If this is a collection, return the child resources.
    def children
      NotImplemented
    end

    # Is this resource a collection?
    def collection?
      NotImplemented
    end

    # Does this resource exist?
    def exist?
      NotImplemented
    end

    # Does the parent resource exist?
    def parent_exists?
      parent.exist?
    end

    # Is the parent resource a collection?
    def parent_collection?
      parent.collection?
    end

    # Return the creation time.
    def creation_date
      raise NotImplemented
    end

    # Return the time of last modification.
    def last_modified
      raise NotImplemented
    end

    # Set the time of last modification.
    def last_modified=(time)
      # Is this correct?
      raise NotImplemented
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      raise NotImplemented
    end

    # Return the resource type. Generally only used to specify
    # resource is a collection.
    def resource_type
      :collection if collection?
    end

    # Return the mime type of this resource.
    def content_type
      raise NotImplemented
    end

    # Return the size in bytes for this resource.
    def content_length
      raise NotImplemented
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      NotImplemented
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      NotImplemented
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      NotImplemented
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      NotImplemented
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest, overwrite=false)
      NotImplemented
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest, overwrite=false)
      NotImplemented
    end

    # args:: Hash of lock arguments
    # Request for a lock on the given resource. A valid lock should lock
    # all descendents. Failures should be noted and returned as an exception
    # using LockFailure.
    # Valid args keys: :timeout -> requested timeout
    #                  :depth -> lock depth
    #                  :scope -> lock scope
    #                  :type -> lock type
    #                  :owner -> lock owner
    # Should return a tuple: [lock_time, locktoken] where lock_time is the
    # given timeout
    # NOTE: See section 9.10 of RFC 4918 for guidance about
    # how locks should be generated and the expected responses
    # (http://www.webdav.org/specs/rfc4918.html#rfc.section.9.10)

    def lock(args)
      unless(@lock_class)
        NotImplemented
      else
        unless(parent_exists?)
          Conflict
        else
          lock_check(args[:scope])
          lock = @lock_class.explicit_locks(@path).find{|l| l.scope == args[:scope] && l.kind == args[:type] && l.user == @user}
          unless(lock)
            token = UUIDTools::UUID.random_create.to_s
            lock = @lock_class.generate(@path, @user, token)
            lock.scope = args[:scope]
            lock.kind = args[:type]
            lock.owner = args[:owner]
            lock.depth = args[:depth].is_a?(Symbol) ? args[:depth] : args[:depth].to_i
            if(args[:timeout])
              lock.timeout = args[:timeout] <= @max_timeout && args[:timeout] > 0 ? args[:timeout] : @max_timeout
            else
              lock.timeout = @default_timeout
            end
            lock.save if lock.respond_to? :save
          end
          begin
            lock_check(args[:type])
          rescue DAV4Rack::LockFailure => lock_failure
            lock.destroy
            raise lock_failure
          rescue HTTPStatus::Status => status
            status
          end
          [lock.remaining_timeout, lock.token]
        end
      end
    end

    # lock_scope:: scope of lock
    # Check if resource is locked. Raise DAV4Rack::LockFailure if locks are in place.
    def lock_check(lock_scope=nil)
      return unless @lock_class
      if(@lock_class.explicitly_locked?(@path))
        raise Locked if @lock_class.explicit_locks(@path).find_all{|l|l.scope == 'exclusive' && l.user != @user}.size > 0
      elsif(@lock_class.implicitly_locked?(@path))
        if(lock_scope.to_s == 'exclusive')
          locks = @lock_class.implicit_locks(@path)
          failure = DAV4Rack::LockFailure.new("Failed to lock: #{@path}")
          locks.each do |lock|
            failure.add_failure(@path, Locked)
          end
          raise failure
        else
          locks = @lock_class.implict_locks(@path).find_all{|l| l.scope == 'exclusive' && l.user != @user}
          if(locks.size > 0)
            failure = LockFailure.new("Failed to lock: #{@path}")
            locks.each do |lock|
              failure.add_failure(@path, Locked)
            end
            raise failure
          end
        end
      end
    end

    # token:: Lock token
    # Remove the given lock
    def unlock(token)
      unless(@lock_class)
        NotImplemented
      else
        token = token.slice(1, token.length - 2)
        if(token.nil? || token.empty?)
          BadRequest
        else
          lock = @lock_class.find_by_token(token)
          if(lock.nil? || lock.user != @user)
            Forbidden
          elsif(lock.path !~ /^#{Regexp.escape(@path)}.*$/)
            Conflict
          else
            lock.destroy
            NoContent
          end
        end
      end
    end


    # Create this resource as collection.
    def make_collection
      NotImplemented
    end

    # other:: Resource
    # Returns if current resource is equal to other resource
    def ==(other)
      path == other.path
    end

    # Name of the resource
    def name
      File.basename(path)
    end

    # Name of the resource to be displayed to the client
    def display_name
      name
    end

    # Available properties
    def properties
      %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength).collect do |prop|
        {:name => prop, :ns_href => DAV_NAMESPACE}
      end
    end

    # name:: String - Property name
    # Returns the value of the given property
    def get_property(element)
      return NotImplemented if (element[:ns_href] != DAV_NAMESPACE)
      case element[:name]
      when 'resourcetype'     then resource_type
      when 'displayname'      then display_name
      when 'creationdate'     then use_ms_compat_creationdate? ? creation_date.httpdate : creation_date.xmlschema
      when 'getcontentlength' then content_length.to_s
      when 'getcontenttype'   then content_type
      when 'getetag'          then etag
      when 'getlastmodified'  then last_modified.httpdate
      else                    NotImplemented
      end
    end

    # name:: String - Property name
    # value:: New value
    # Set the property to the given value
    def set_property(element, value)
      return NotImplemented if (element[:ns_href] != DAV_NAMESPACE)
      case element[:name]
      when 'resourcetype'    then self.resource_type = value
      when 'getcontenttype'  then self.content_type = value
      when 'getetag'         then self.etag = value
      when 'getlastmodified' then self.last_modified = Time.httpdate(value)
      else                   NotImplemented
      end
    end

    # name:: Property name
    # Remove the property from the resource
    def remove_property(element)
      Forbidden
    end

    # name:: Name of child
    # Create a new child with the given name
    # NOTE:: Include trailing '/' if child is collection
    def child(name)
      new_public = public_path.dup
      new_public = new_public + '/' unless new_public[-1,1] == '/'
      new_public = '/' + new_public unless new_public[0,1] == '/'
      new_path = path.dup
      new_path = new_path + '/' unless new_path[-1,1] == '/'
      new_path = '/' + new_path unless new_path[0,1] == '/'
      self.class.new("#{new_public}#{name}", "#{new_path}#{name}", request, response, options.merge(:user => @user))
    end

    # Return parent of this resource
    def parent
      unless(@path.to_s.empty?)
        self.class.new(
          File.split(@public_path).first,
          File.split(@path).first,
          @request,
          @response,
          @options.merge(
            :user => @user
          )
        )
      end
    end

    # Return list of descendants
    def descendants
      list = []
      children.each do |child|
        list << child
        list.concat(child.descendants)
      end
      list
    end

    # Index page template for GETs on collection
    def index_page
      '<html><head> <title>%s</title>
      <meta http-equiv="content-type" content="text/html; charset=utf-8" /></head>
      <body> <h1>%s</h1> <hr /> <table> <tr> <th class="name">Name</th>
      <th class="size">Size</th> <th class="type">Type</th>
      <th class="mtime">Last Modified</th> </tr> %s </table> <hr /> </body></html>'
    end

    def properties_xml_with_depth(process_properties, depth)
      partial_document = Ox::Document.new()

      partial_document << self.properties_xml(process_properties)

      case depth
      when 0
      when 1
        self.children.each do |resource|
          partial_document << resource.properties_xml(process_properties)
        end
      else
        self.descendants.each do |resource|
          partial_document << resource.properties_xml(process_properties)
        end
      end

      Ox.dump(partial_document, {indent: -1})
    end

    D_RESPONSE = 'D:response'
    D_HREF = 'D:href'

    def properties_xml(process_properties)
      response = Ox::Element.new(D_RESPONSE)

      unless(propstat_relative_path)
        response << (Ox::Element.new(D_HREF) << "#{request.scheme}://#{request.host}:#{request.port}#{url_format}")
      else
        response << (Ox::Element.new(D_HREF) << url_format)
      end

      process_properties.each do |type, properties|
        propstats(response, self.send("#{type}_properties_with_status",properties))
      end
      response
    end

    def get_properties_with_status(properties)
      stats = Hash.new { |h, k| h[k] = [] }
      properties.each do |property|
        val = self.get_property(property[:element])
        if val.is_a?(Class)
          stats[val] << property[:element]
        else
          stats[OK] << [property[:element], val]
        end
      end
      stats
    end

    def set_properties_with_status(properties)
      stats = Hash.new { |h, k| h[k] = [] }
      properties.each do |property|
        val = self.set_property(property[:element], property[:value])
        if val.is_a?(Class)
          stats[val] << property[:element]
        else
          stats[OK] << [property[:element], val]
        end
      end
      stats
    end

    # resource:: Resource
    # elements:: Property hashes (name, namespace, children)
    # Removes the given properties from a resource
    def remove_properties_with_status(properties)
      remove_property(properties.first[:element])
      []
    end

    # xml:: Nokogiri::XML::Builder
    # stats:: Array of stats
    # Build propstats response
    D_PROPSTAT = 'D:propstat'
    D_PROP = 'D:prop'
    D_STATUS = 'D:status'

    def propstats(response, stats)
      return if stats.empty?
      stats.each do |status, props|
        propstat = Ox::Element.new(D_PROPSTAT)
        prop = Ox::Element.new(D_PROP)

        props.each do |element, value|
          prefix = namespaces[element[:ns_href]]
          if(value.is_a?(Symbol))
            prop << (Ox::Element.new("#{prefix}:#{element[:name]}") << Ox::Element.new("#{prefix}:#{value}"))
          else
            prop_element = Ox::Element.new("#{prefix}:#{element[:name]}")
            prop_element << value.to_s if value
            prop << prop_element
          end
        end

        propstat << prop
        propstat << (Ox::Element.new(D_STATUS) << "#{http_version} #{status.status_line}")

        response << propstat
      end
    end

    # s:: string
    # Escape URL string
    def url_format
      ret = URI.escape(public_path)
      if collection? and ret[-1,1] != '/'
        ret += '/'
      end
      # Additionally escape square brackets, otherwise files with
      # file names like file[1].pdf are not visible in some WebDAV clients
      URI.escape ret, '[]'
    end

    # Does client allow GET redirection
    # TODO: Get a comprehensive list in here.
    # TODO: Allow this to be dynamic so users can add regexes to match if they know of a client
    # that can be supported that is not listed.
    def allows_redirect?
      [
        %r{cyberduck}i,
        %r{konqueror}i
      ].any? do |regexp|
        (request.respond_to?(:user_agent) ? request.user_agent : request.env['HTTP_USER_AGENT']).to_s =~ regexp
      end
    end

    def use_compat_mkcol_response?
      @options[:compat_mkcol] || @options[:compat_all]
    end

    # Returns true if using an MS client
    def use_ms_compat_creationdate?
      if(@options[:compat_ms_mangled_creationdate] || @options[:compat_all])
        is_ms_client?
      end
    end

    # Basic user agent testing for MS authored client
    def is_ms_client?
      [%r{microsoft-webdav}i, %r{microsoft office}i].any? do |regexp|
        (request.respond_to?(:user_agent) ? request.user_agent : request.env['HTTP_USER_AGENT']).to_s =~ regexp
      end
    end

    # Callback function that adds additional properties to the propfind REQUEST
    # These properties will then be parsed and processed as though they were sent
    # by the client. This makes sure we can add whatever property we want
    # to the response and make it look like the client asked for them.
    def propfind_add_additional_properties(properties)
      # Default implementation doesn't need to add anything
      properties
    end

    protected

    # Request environment variables
    def env
      @request.env
    end

    # Returns authentication credentials if available in form of [username,password]
    # TODO: Add support for digest
    def auth_credentials
      auth = Rack::Auth::Basic::Request.new(request.env)
      auth.provided? && auth.basic? ? auth.credentials : [nil,nil]
    end

  end

end
