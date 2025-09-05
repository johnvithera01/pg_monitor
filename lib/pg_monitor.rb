# lib/pg_monitor.rb
require_relative 'pg_monitor/config'
require_relative 'pg_monitor/connection'
require_relative 'pg_monitor/email_sender'
require_relative 'pg_monitor/metrics'
require_relative 'pg_monitor/collectors/base_collector'
require_relative 'pg_monitor/collectors/critical_metrics'
require_relative 'pg_monitor/collectors/security_metrics'
require_relative 'pg_monitor/collectors/performance_metrics'
require_relative 'pg_monitor/logger'

module PgMonitor
  VERSION = '2.0.0'
  
  class Monitor
    def initialize(config_path = nil)
      @config = Config.new(config_path)
      @logger = Logger.new(@config)
      @connection = Connection.new(@config)
      @email_sender = EmailSender.new(@config)
      @alert_messages = []
    end

    def run(frequency_level)
      @logger.info("Starting pg_monitor v#{VERSION} with frequency: #{frequency_level}")
      
      begin
        @connection.connect
        
        case frequency_level
        when 'high'
          run_critical_monitoring
        when 'medium'
          run_performance_monitoring
        when 'low'
          run_maintenance_monitoring
        when 'security'
          run_security_monitoring
        else
          @logger.error("Unknown frequency level: #{frequency_level}")
          return false
        end
        
        send_alerts if @alert_messages.any?
        update_prometheus_metrics
        
      rescue => e
        @logger.error("Monitor failed: #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        false
      ensure
        @connection.close
      end
    end

    private

    def run_critical_monitoring
      collector = Collectors::CriticalMetrics.new(@connection, @config, @alert_messages)
      collector.monitor
    end

    def run_performance_monitoring
      collector = Collectors::PerformanceMetrics.new(@connection, @config, @alert_messages)
      collector.monitor
    end

    def run_maintenance_monitoring
      collector = Collectors::MaintenanceMetrics.new(@connection, @config, @alert_messages)
      collector.monitor
    end

    def run_security_monitoring
      collector = Collectors::SecurityMetrics.new(@connection, @config, @alert_messages)
      collector.monitor
    end

    def send_alerts
      return unless @alert_messages.any?
      
      subject = "pg_monitor Alert - #{@alert_messages.size} issue(s) detected"
      body = @alert_messages.join("\n\n")
      
      @email_sender.send_alert_email(subject, body, "combined_alert")
    end

    def update_prometheus_metrics
      result = {
        alerts_count: @alert_messages.size,
        last_run: Time.now.to_i
      }
      
      Metrics.update_from(result)
    end
  end
end
