# lib/pg_monitor/logger.rb
require 'logger'
require 'json'

module PgMonitor
  class Logger
    LEVELS = {
      'debug' => ::Logger::DEBUG,
      'info' => ::Logger::INFO,
      'warn' => ::Logger::WARN,
      'error' => ::Logger::ERROR,
      'fatal' => ::Logger::FATAL
    }.freeze

    def initialize(config)
      @config = config
      @logger = create_logger
    end

    def debug(message, context = {})
      log(:debug, message, context)
    end

    def info(message, context = {})
      log(:info, message, context)
    end

    def warn(message, context = {})
      log(:warn, message, context)
    end

    def error(message, context = {})
      log(:error, message, context)
    end

    def fatal(message, context = {})
      log(:fatal, message, context)
    end

    private

    def create_logger
      FileUtils.mkdir_p(File.dirname(@config.log_file))
      
      logger = ::Logger.new(@config.log_file, 'daily')
      logger.level = LEVELS[@config.log_level] || ::Logger::INFO
      logger.formatter = proc do |severity, datetime, progname, msg|
        timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
        "[#{timestamp}] #{severity}: #{msg}\n"
      end
      
      logger
    end

    def log(level, message, context)
      log_entry = {
        timestamp: Time.now.iso8601,
        level: level.to_s.upcase,
        message: message,
        context: context,
        host: @config.db_host,
        database: @config.db_name
      }

      if context.any?
        @logger.send(level, "#{message} - Context: #{context.to_json}")
      else
        @logger.send(level, message)
      end
    end
  end
end
