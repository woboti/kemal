require "http"

module Kemal
  # Initializes the context with default values, such as
  # *Content-Type* or *X-Powered-By* headers.
  class InitHandler
    include HTTP::Handler

    def initialize(@config : Kemal::Config = Config::INSTANCE)
    end

    def call(context : HTTP::Server::Context)
      context.config = @config
      context.response.headers.add "X-Powered-By", "Kemal" if @config.powered_by_header?
      context.response.content_type = "text/html" unless context.response.headers.has_key?("Content-Type")
      context.response.headers.add "Date", HTTP.format_time(Time.utc)
      context.websocket_route = @config.web_socket_handler.lookup_ws_route(context.request.path)
      context.route = @config.route_handler.lookup_route(context.request.method.as(String), context.request.path)
      call_next context
    end
  end
end
