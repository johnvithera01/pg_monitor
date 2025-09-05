# lib/pg_monitor/config.rb
require 'yaml'
require 'fileutils'

module PgMonitor
  class Config
    REQUIRED_ENV_VARS = %w[PG_USER PG_PASSWORD EMAIL_PASSWORD].freeze
    
    attr_reader :db_host, :db_port, :db_name, :db_user, :db_password
    attr_reader :sender_email, :sender_password, :receiver_email, :smtp_address, :smtp_port, :smtp_domain
    attr_reader :iostat_threshold_kb_s, :iostat_device, :cpu_alert_threshold
    attr_reader :query_alert_threshold_minutes, :query_kill_threshold_minutes
    attr_reader :heap_cache_hit_ratio_min, :index_cache_hit_ratio_min, :table_growth_threshold_percent
    attr_reader :alert_cooldown_minutes, :last_alert_file, :last_deadlock_file
    attr_reader :log_file, :log_level
    attr_reader :pg_log_path, :pg_log_file_pattern
    attr_reader :auto_kill_rogue_processes
    attr_reader :disk_space_threshold_percent
    attr_reader :replication_lag_bytes_threshold, :replication_lag_time_threshold_seconds
    attr_reader :config_file_path

    def initialize(config_path = nil)
      @config_file_path = config_path || default_config_path
      validate_config_file!
      validate_environment_variables!
      load_configuration
    end

    def valid?
      @validation_errors.empty?
    end

    def validation_errors
      @validation_errors ||= []
    end

    private

    def default_config_path
      File.expand_path('../../config/pg_monitor_config.yml', __dir__)
    end

    def validate_config_file!
      unless File.exist?(@config_file_path)
        raise ConfigurationError, "Configuration file not found: #{@config_file_path}"
      end
    end

    def validate_environment_variables!
      missing_vars = REQUIRED_ENV_VARS.select { |var| ENV[var].nil? || ENV[var].empty? }
      
      unless missing_vars.empty?
        raise ConfigurationError, 
              "Missing required environment variables: #{missing_vars.join(', ')}"
      end
    end

    def load_configuration
      @validation_errors = []
      config = YAML.load_file(@config_file_path)

      load_database_config(config['database'])
      load_email_config(config['email'])
      load_thresholds_config(config['thresholds'])
      load_cooldown_config(config['cooldown'])
      load_logging_config(config['logging'])
      load_postgresql_logs_config(config['postgresql_logs'])
      load_features_config(config['features'])

      validate_configuration!
    end

    def load_database_config(db_config)
      @db_host = db_config['host'] || 'localhost'
      @db_port = db_config['port'] || 5432
      @db_name = db_config['name'] || 'postgres'
      @db_user = ENV['PG_USER']
      @db_password = ENV['PG_PASSWORD']
    end

    def load_email_config(email_config)
      @sender_email = email_config['sender_email']
      @sender_password = ENV['EMAIL_PASSWORD']
      @receiver_email = email_config['receiver_email']
      @smtp_address = email_config['smtp_address'] || 'smtp.gmail.com'
      @smtp_port = email_config['smtp_port'] || 587
      @smtp_domain = email_config['smtp_domain'] || 'gmail.com'
    end

    def load_thresholds_config(thresholds)
      @iostat_threshold_kb_s = thresholds['iostat_threshold_kb_s'] || 50000
      @iostat_device = thresholds['iostat_device'] || 'vda'
      @cpu_alert_threshold = thresholds['cpu_threshold_percent'] || 80
      @query_alert_threshold_minutes = thresholds['query_alert_threshold_minutes'] || 5
      @query_kill_threshold_minutes = thresholds['query_kill_threshold_minutes'] || 10
      @heap_cache_hit_ratio_min = thresholds['heap_cache_hit_ratio_min'] || 95
      @index_cache_hit_ratio_min = thresholds['index_cache_hit_ratio_min'] || 90
      @table_growth_threshold_percent = thresholds['table_growth_threshold_percent'] || 20
      @disk_space_threshold_percent = thresholds['disk_space_threshold_percent'] || 90
      @replication_lag_bytes_threshold = thresholds['replication_lag_bytes_threshold'] || 104857600
      @replication_lag_time_threshold_seconds = thresholds['replication_lag_time_threshold_seconds'] || 300
    end

    def load_cooldown_config(cooldown)
      @alert_cooldown_minutes = cooldown['alert_cooldown_minutes'] || 60
      @last_alert_file = cooldown['last_alert_file'] || '/tmp/pg_monitor_last_alerts.json'
      @last_deadlock_file = cooldown['last_deadlock_file'] || '/tmp/pg_monitor_last_deadlock_count.json'
      
      # Ensure directories exist
      FileUtils.mkdir_p(File.dirname(@last_alert_file))
      FileUtils.mkdir_p(File.dirname(@last_deadlock_file))
    end

    def load_logging_config(logging)
      @log_file = logging['log_file'] || '/var/log/pg_monitor/pg_monitor.log'
      @log_level = logging['log_level'] || 'info'
      
      # Ensure log directory exists
      FileUtils.mkdir_p(File.dirname(@log_file))
    end

    def load_postgresql_logs_config(pg_logs)
      @pg_log_path = pg_logs['path']
      @pg_log_file_pattern = pg_logs['file_pattern'] || 'postgresql-*.log'
    end

    def load_features_config(features)
      @auto_kill_rogue_processes = features['auto_kill_rogue_processes'] || false
    end

    def validate_configuration!
      validate_thresholds
      validate_email_config
      validate_paths
    end

    def validate_thresholds
      add_error("CPU threshold must be between 1 and 100") unless (1..100).include?(@cpu_alert_threshold)
      add_error("Heap cache hit ratio must be between 1 and 100") unless (1..100).include?(@heap_cache_hit_ratio_min)
      add_error("Index cache hit ratio must be between 1 and 100") unless (1..100).include?(@index_cache_hit_ratio_min)
      add_error("Query alert threshold must be positive") unless @query_alert_threshold_minutes > 0
      add_error("Alert cooldown must be positive") unless @alert_cooldown_minutes > 0
    end

    def validate_email_config
      add_error("Sender email is required") if @sender_email.nil? || @sender_email.empty?
      add_error("Receiver email is required") if @receiver_email.nil? || @receiver_email.empty?
      add_error("SMTP address is required") if @smtp_address.nil? || @smtp_address.empty?
    end

    def validate_paths
      add_error("PostgreSQL log path does not exist") if @pg_log_path && !Dir.exist?(@pg_log_path)
    end

    def add_error(message)
      @validation_errors << message
    end
  end

  class ConfigurationError < StandardError; end
end
