require "http"
require "json"
require "log"
require "uri"
require "./kemal/*"
require "./kemal/ext/*"
require "./kemal/helpers/*"

module Kemal
  Log = ::Log.for(self)

  # Overload of `self.run` with the default startup logging.
  def self.run(port : Int32?, args = ARGV, trap_signal : Bool = true)
    run(port, args, trap_signal) { }
  end

  # Overload of `self.run` without port.
  def self.run(args = ARGV, trap_signal : Bool = true)
    run(nil, args: args, trap_signal: trap_signal)
  end

  # Overload of `self.run` to allow just a block.
  def self.run(args = ARGV, &block)
    run(nil, args: args, trap_signal: true, &block)
  end

  # The command to run a `Kemal` application.
  #
  # If *port* is not given Kemal will use `Kemal::Config#port`
  #
  # To use custom command line arguments, set args to nil
  #
  def self.run(port : Int32? = nil, args = ARGV, trap_signal : Bool = true, &)
    Kemal::CLI.new args, Kemal.config
    config = Kemal.config
    config.setup
    config.port = port if port

    # Test environment doesn't need to have signal trap and logging.
    if config.env != "test"
      setup_404
      setup_trap_signal if trap_signal
    end

    server = config.server ||= HTTP::Server.new(config.handlers)

    Kemal.server.running = true

    yield config

    # Abort if block called `Kemal.stop`
    return if !Kemal.server.running

    if config.env != "test"
      if !server.each_address { |_| break true }
        {% if flag?(:without_openssl) %}
          server.bind_tcp(config.host_binding, config.port)
        {% else %}
          if ssl = config.ssl
            server.bind_tls(config.host_binding, config.port, ssl)
          else
            server.bind_tcp(config.host_binding, config.port)
          end
        {% end %}
      end
    end

    display_startup_message(config, server)

    server.listen if config.env != "test"
  end

  def self.display_startup_message(config, server)
    if config.env != "test"
      addresses = server.addresses.join ", " { |address| "#{config.scheme}://#{address}" }
      Log.info { "[#{config.env}] #{config.app_name} is ready to lead at #{addresses}" }
    else
      Log.info { "[#{config.env}] #{config.app_name} is running in test mode. Server not listening" }
    end
  end

  def self.stop
    raise "#{Kemal.config.app_name} is already stopped. Cannot stop an already stopped server." if !Kemal.server.running
    if handler = Kemal.server.config.server
      handler.close unless handler.closed?
      Kemal.server.running = false
    else
      raise "Cannot stop #{Kemal.config.app_name}: server instance is not set. Please ensure Kemal.run has been called before calling Kemal.stop."
    end
  end

  private def self.setup_404
    unless Kemal.config.error_handlers.has_key?(404)
      error 404 do
        render_404
      end
    end
  end

  private def self.setup_trap_signal
    Process.on_terminate do
      Log.info { "#{Kemal.config.app_name} is going to take a rest!" } if Kemal.config.shutdown_message
      Kemal.stop
      exit
    end
  end

  def self.server(&)
    yield @@server_instance || (@@server_instance = Server.new Config::INSTANCE)
  end

  def self.server
    @@server_instance || (@@server_instance = Server.new Config::INSTANCE)
  end
end
