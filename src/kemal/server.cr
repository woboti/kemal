module Kemal
  class Server

    getter config : Kemal::Config
    getter handler : HTTP::Server?
    property running = false

    Log = ::Log.for(self)

    def initialize(@config : Kemal::Config)
    end

    def initialize(@config : Kemal::Config, &)
      with self yield self
    end

    def init
      @config.setup
    end

    # Overload of `run` with the default startup logging.
    def run(port : Int32?, trap_signal : Bool = true)
      run(port, trap_signal) { }
    end

    # Overload of `run` without port.
    def run(trap_signal : Bool = true)
      run(nil, trap_signal: trap_signal)
    end

    # Overload of `run` to allow just a block.
    def run(&block)
      run(nil, trap_signal: true, &block)
    end

    # The command to run a `Kemal` application.
    #
    # If *port* is not given Kemal will use `Kemal::Config#port`
    #
    def run(port : Int32? = nil, trap_signal : Bool = true, &)
      init
      config.port = port if port

      # Test environment doesn't need to have signal trap and logging.
      if config.env != "test"
        setup_404
        setup_trap_signal if trap_signal
      end

      h = @handler = config.server ||= HTTP::Server.new(config.handlers)

      @running = true

      yield self

      # Abort if block called `server.stop`
      return if !@running

      if config.env != "test"
        if !h.each_address { |_| break true }
          {% if flag?(:without_openssl) %}
            h.bind_tcp(config.host_binding, config.port)
          {% else %}
            if ssl = config.ssl
              h.bind_tls(config.host_binding, config.port, ssl)
            else
              h.bind_tcp(config.host_binding, config.port)
            end
          {% end %}
        end
      end

      display_startup_message(config, h)

      h.listen if config.env != "test"
    end

    def display_startup_message(config, handler)
      if config.env != "test"
        addresses = handler.addresses.join ", " { |address| "#{config.scheme}://#{address}" }
        Log.info { "[#{config.env}] #{config.app_name} is ready to lead at #{addresses}" }
      else
        Log.info { "[#{config.env}] #{config.app_name} is running in test mode. Server not listening" }
      end
    end

    def stop
      raise "#{config.app_name} is already stopped. Cannot stop an already stopped server." if !@running
      if h = @handler
        h.close unless h.closed?
        @running = false
      else
        raise "Cannot stop #{config.app_name}: server instance is not set. Please ensure server.run has been called before calling server.stop."
      end
    end

    private def setup_404
      unless config.error_handlers.has_key?(404)
        error 404 do
          render_404
        end
      end
    end

    private def setup_trap_signal
      Process.on_terminate do
        Log.info { "#{config.app_name} is going to take a rest!" } if config.shutdown_message
        stop
        exit
      end
    end

    # Defines a route for the given HTTP method.
    #
    # NOTE: The path must start with a `/`.
    #
    # ```
    # server.get "/hello" do |env|
    #   "Hello World!"
    # end
    #
    # server.post "/users" do |env|
    #   "User created"
    # end
    # ```
    {% for method in HTTP_METHODS %}
      def {{ method.id }}(path : String, &block : HTTP::Server::Context -> _)
        raise Kemal::Exceptions::InvalidPathStartException.new({{ method }}, path) unless Kemal::Utils.path_starts_with_slash?(path)
        @config.route_handler.add_route({{ method }}.upcase, path, &block)
      end
    {% end %}

    # Defines a WebSocket route.
    #
    # NOTE: The path must start with a `/`.
    #
    # ```
    # ws "/chat" do |socket, env|
    #   socket.on_message do |msg|
    #     socket.send "Echo: #{msg}"
    #   end
    # end
    # ```
    def ws(path : String, &block : HTTP::WebSocket, HTTP::Server::Context ->)
      raise Kemal::Exceptions::InvalidPathStartException.new("ws", path) unless Kemal::Utils.path_starts_with_slash?(path)
      @config.web_socket_handler.add_route path, &block
    end

    # Defines an error handler for the given HTTP status code.
    #
    # ```
    # error 404 do |env|
    #   "Page not found"
    # end
    # ```
    def error(status_code : Int32, &block : HTTP::Server::Context, Exception -> _)
      @config.add_error_handler status_code, &block
    end

    # Defines an error handler for the given `HTTP::Status`.
    #
    # ```
    # error :not_found do |env|
    #   "Page not found"
    # end
    # ```
    def error(status : HTTP::Status, &block : HTTP::Server::Context, Exception -> _)
      @config.add_error_handler status.code, &block
    end

    # Defines an error handler for the given exception type.
    #
    # ```
    # error MyCustomException do |env, ex|
    #   "Error: #{ex.message}"
    # end
    # ```
    def error(exception : Exception.class, &block : HTTP::Server::Context, Exception -> _)
      @config.add_exception_handler exception, &block
    end

    # Defines filters that run before or after requests.
    #
    # Available methods:
    # - `before_all`, `before_get`, `before_post`, `before_put`, `before_patch`, `before_delete`, `before_options`
    # - `after_all`, `after_get`, `after_post`, `after_put`, `after_patch`, `after_delete`, `after_options`
    #
    # ```
    # server.before_all do |env|
    #   env.response.content_type = "application/json"
    # end
    #
    # server.before_get "/admin/*" do |env|
    #   # Authentication check
    # end
    #
    # # Multiple paths
    # server.after_post ["/users", "/posts"] do |env|
    #   # Logging
    # end
    # ```
    {% for type in ["before", "after"] %}
      {% for method in FILTER_METHODS %}
        def {{ type.id }}_{{ method.id }}(path : String = "*", &block : HTTP::Server::Context -> _)
        @config.filter_handler.{{ type.id }}({{ method }}.upcase, path, &block)
        end

        def {{ type.id }}_{{ method.id }}(paths : Enumerable(String), &block : HTTP::Server::Context -> _)
          paths.each do |path|
            @config.filter_handler.{{ type.id }}({{ method }}.upcase, path, &block)
          end
        end
      {% end %}
    {% end %}

    # Adds a `HTTP::Handler` (middleware) to the handler chain.
    # The handler runs for all requests.
    #
    # ```
    # use MyHandler.new
    # ```
    def use(handler : HTTP::Handler)
      @config.add_handler(handler)
    end

    # Adds a `HTTP::Handler` (middleware) at a specific position in the handler chain.
    #
    # ```
    # use MyHandler.new, position: 1
    # ```
    def use(handler : HTTP::Handler, position : Int32)
      @config.add_handler(handler, position)
    end

    # Adds a `HTTP::Handler` (middleware) that only runs for requests matching the path prefix.
    #
    # ```
    # use "/api", AuthHandler.new
    # ```
    #
    # The handler will execute for:
    # - Exact match: `/api`
    # - Prefix match: `/api/users`, `/api/posts/1`
    #
    # But NOT for:
    # - `/`, `/apiv2`, `/other`
    def use(path : String, handler : HTTP::Handler)
      @config.add_handler(Kemal::PathHandler.new(path, handler))
    end

    # Adds multiple `HTTP::Handler` (middlewares) for a specific path prefix.
    #
    # ```
    # use "/api", [AuthHandler.new, RateLimiter.new, CorsHandler.new]
    # ```
    def use(path : String, handlers : Enumerable(HTTP::Handler))
      handlers.each do |handler|
        use(path, handler)
      end
    end

    # Mounts a router without additional prefix.
    #
    # ```
    # api = Kemal::Router.new
    # api.get "/users" do |env|
    #   "users"
    # end
    #
    # mount api
    # # Result: GET /users
    # ```
    def mount(router : Kemal::Router)
      router.register_routes(@config)
    end

    # Mounts a router at the given *path* prefix.
    #
    # NOTE: The path must start with a `/`.
    #
    # All routes defined in the router will be prefixed with the given path.
    #
    # ```
    # api = Kemal::Router.new
    # api.get "/users" do |env|
    #   "users"
    # end
    #
    # mount "/api/v1", api
    # # Result: GET /api/v1/users
    # ```
    def mount(path : String, router : Kemal::Router)
      router.register_routes(@config, path)
    end

    # Sets public folder from which the static assets will be served.
    #
    # By default this is `/public` not `src/public`.
    def public_folder(path : String)
      @config.public_folder = path
    end

    # Enables / Disables logging.
    # This is enabled by default.
    #
    # ```
    # logging false
    # ```
    def logging(status : Bool)
      @config.logging = status
    end

    # This is used to replace the built-in `Kemal::LogHandler` with a custom logger.
    #
    # A custom logger must inherit from `Kemal::BaseLogHandler` and must implement
    # `call(context)`, `write(message)` methods.
    #
    # ```
    # class MyCustomLogger < Kemal::BaseLogHandler
    #   def call(context)
    #     puts "I'm logging some custom stuff here."
    #     call_next(context) # => This calls the next handler
    #   end
    #
    #   # This is used from `log` method.
    #   def write(message)
    #     STDERR.puts message # => Logs the output to STDERR
    #   end
    # end
    # ```
    #
    # Now that we have a custom logger here's how we use it
    #
    # ```
    # logger MyCustomLogger.new
    # ```
    def logger(logger : Kemal::BaseLogHandler)
      @config.logger = logger
    end

    # Enables / Disables static file serving.
    # This is enabled by default.
    #
    # ```
    # serve_static false
    # ```
    #
    # Static server also have some advanced customization options like `dir_listing` and
    # `gzip`.
    #
    # ```
    # serve_static {"gzip" => true, "dir_listing" => false}
    # ```
    def serve_static(status : (Bool | Hash))
      @config.serve_static = status
    end

    # Adds headers to `Kemal::StaticFileHandler`. This is especially useful for `CORS`.
    #
    # ```
    # static_headers do |env, filepath, filestat|
    #   if filepath =~ /\.html$/
    #     env.response.headers.add("Access-Control-Allow-Origin", "*")
    #   end
    #   env.response.headers.add("Content-Size", filestat.size.to_s)
    # end
    # ```
    def static_headers(&headers : HTTP::Server::Context, String, File::Info ->)
      @config.static_headers = headers
    end
  end
end