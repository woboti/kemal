module Kemal
  class Server

    getter config : Kemal::Config
    getter handler : HTTP::Server?
    getter running = false

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
  end
end