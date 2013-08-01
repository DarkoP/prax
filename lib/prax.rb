require 'socket'
require 'thread'
require 'prax/config'
require 'prax/logger'
require 'prax/microserver'
require 'prax/worker'
require 'prax/spawner'
require 'prax/handler'

module Prax
  include Logger

  class Error < StandardError; end
  class NoSuchApp < Error; end
  class CantStartApp < Error; end

  class Pool < MicroWorker
    def perform(socket, ssl = nil)
      Handler.new(socket, ssl).handle
    end
  end

  class Server < MicroServer
    include Worker

    self.worker_class = Pool
    self.worker_size = Config.threads_count

    def initialize
      @ssl_crt = File.expand_path('../../ssl/server.crt', __FILE__)
      @ssl_key = File.expand_path('../../ssl/server.key', __FILE__)
      super
    end

    def started
      servers = @listeners.map { |server| ":#{server.addr[1]}" }
      Prax.logger.info("Prax is ready to receive connections on #{servers.join(' and ')}.")
    end
  end

  def self.run(options = {})
    @server = Server.new
    @daemon = options[:daemon]

    %w{INT TERM QUIT}.each { |signal| Signal.trap(signal) { exit } }
    Signal.trap('EXIT') { stop }

    @server.add_tcp_listener(Config.http_port)
    @server.add_ssl_listener(Config.https_port)
    @server.run
  end

  def self.stop(sync = true)
    @server.stop(sync)
  end
end
