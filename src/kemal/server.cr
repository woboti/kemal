module Kemal

  class Server

    getter config : Kemal::Config
    property running = false

    def initialize(@config : Kemal::Config)
    end

    def init
      @config.setup
    end
  end
end