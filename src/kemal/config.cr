module Kemal
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  # Stores all the configuration options for a Kemal application.
  class Config

    INSTANCE                  = Config.new

    getter handlers           = [] of HTTP::Handler
    getter custom_handlers    = [] of Tuple(Int32?, HTTP::Handler)
    getter filter_handlers    = [] of HTTP::Handler
    getter error_handlers     = {} of Int32 => HTTP::Server::Context, Exception -> String
    getter exception_handlers = {} of Exception.class => HTTP::Server::Context, Exception -> String

    @init_handler : Kemal::InitHandler?
    @route_handler : Kemal::RouteHandler?
    @web_socket_handler : Kemal::WebSocketHandler?
    @filter_handler : Kemal::FilterHandler?
    @head_request_handler : Kemal::HeadRequestHandler?
    @override_method_handler : Kemal::OverrideMethodHandler?
    @exception_handler : Kemal::ExceptionHandler?

    {% if flag?(:without_openssl) %}
      @ssl : Bool?
    {% else %}
      @ssl : OpenSSL::SSL::Context::Server?
    {% end %}

    property app_name, host_binding, ssl, port, env, public_folder, logging
    property always_rescue, server : HTTP::Server?, extra_options, shutdown_message
    property serve_static : (Bool | Hash(String, Bool))
    property static_headers : (HTTP::Server::Context, String, File::Info ->)?
    property? powered_by_header : Bool = true
    property max_route_cache_size : Int32
    property max_request_body_size : Int32

    def initialize
      @app_name = "Kemal"
      @host_binding = "0.0.0.0"
      @port = 3000
      @env = ENV["KEMAL_ENV"]? || "development"
      @serve_static = {"dir_listing" => false, "gzip" => true, "dir_index" => false}
      @public_folder = "./public"
      @logging = true
      @logger = nil
      @error_handler = nil
      @always_rescue = true
      @router_included = false
      @default_handlers_setup = false
      @shutdown_message = true
      @handler_position = 0
      @max_route_cache_size = 1024
      @max_request_body_size = 8 * 1024 * 1024 # 8MB
    end

    def init_handler
      @init_handler ||= Kemal::InitHandler.new(self)
    end

    def route_handler
      @route_handler ||= Kemal::RouteHandler.new(self)
    end

    def web_socket_handler
      @web_socket_handler ||=  Kemal::WebSocketHandler.new
    end

    def filter_handler
      @filter_handler ||=  Kemal::FilterHandler.new(self)
    end

    def head_request_handler
      @head_request_handler ||=  Kemal::HeadRequestHandler.new
    end

    def override_method_handler
      @override_method_handler ||=  Kemal::OverrideMethodHandler.new
    end

    def exception_handler
      @exception_handler ||=  Kemal::ExceptionHandler.new
    end

    @[Deprecated("Use standard library Log")]
    def logger
      @logger || NullLogHandler.new
    end

    # :nodoc:
    def logger?
      @logger
    end

    @[Deprecated("Use standard library Log")]
    def logger=(logger : Kemal::BaseLogHandler)
      @logger = logger
    end

    def scheme
      ssl ? "https" : "http"
    end

    def clear
      @powered_by_header = true
      @router_included = false
      @handler_position = 0
      @default_handlers_setup = false
      @max_route_cache_size = 1024
      @max_request_body_size = 8 * 1024 * 1024
      @handlers.clear
      @custom_handlers.clear
      @filter_handlers.clear
      @error_handlers.clear
    end

    def handlers=(handlers : Array(HTTP::Handler))
      # TODO::Why?
      clear
      @handlers.replace(handlers)
    end

    def add_handler(handler : HTTP::Handler)
      @custom_handlers << {nil, handler}
    end

    def add_handler(handler : HTTP::Handler, position : Int32)
      @custom_handlers << {position, handler}
    end

    def add_filter_handler(handler : HTTP::Handler)
      @filter_handlers << handler
    end

    # Adds an error handler for the given HTTP status code
    def add_error_handler(status_code : Int32, &handler : HTTP::Server::Context, Exception -> _)
      @error_handlers[status_code] = ->(context : HTTP::Server::Context, error : Exception) { handler.call(context, error).to_s }
    end

    # Adds an error handler for the given exception
    def add_exception_handler(exception : Exception.class, &handler : HTTP::Server::Context, Exception -> _)
      @exception_handlers[exception] = ->(context : HTTP::Server::Context, error : Exception) { handler.call(context, error).to_s }
    end

    def extra_options(&@extra_options : OptionParser ->)
    end

    def setup
      unless @default_handlers_setup && @router_included
        setup_init_handler
        setup_log_handler
        setup_head_request_handler
        setup_error_handler
        setup_static_file_handler
        setup_custom_handlers
        setup_filter_handlers
        @default_handlers_setup = true
        @router_included = true
        @handlers.insert(@handlers.size, web_socket_handler)
        @handlers.insert(@handlers.size, route_handler)
      end
    end

    private def setup_init_handler
      @handlers.insert(@handler_position, init_handler)
      @handler_position += 1
    end

    private def setup_log_handler
      return unless @logging

      log_handler = @logger || Kemal::RequestLogHandler.new

      @handlers.insert(@handler_position, log_handler)
      @handler_position += 1
    end

    private def setup_head_request_handler
      @handlers.insert(@handler_position, head_request_handler)
      @handler_position += 1
    end

    private def setup_error_handler
      if @always_rescue
        handler = @error_handler ||= Kemal::ExceptionHandler.new
        @handlers.insert(@handler_position, handler)
        @handler_position += 1
      end
    end

    private def setup_static_file_handler
      if @serve_static.is_a?(Hash)
        @handlers.insert(@handler_position, Kemal::StaticFileHandler.new(@public_folder))
        @handler_position += 1
      end
    end

    private def setup_custom_handlers
      @custom_handlers.each do |ch0, ch1|
        position = ch0
        @handlers.insert (position || @handler_position), ch1
        @handler_position += 1
      end
    end

    private def setup_filter_handlers
      @filter_handlers.each do |handler|
        @handlers.insert(@handler_position, handler)
      end
    end
  end

  def self.config(&)
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
