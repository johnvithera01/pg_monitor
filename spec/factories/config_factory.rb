# spec/factories/config_factory.rb
require 'factory_bot'

FactoryBot.define do
  factory :config, class: PgMonitor::Config do
    skip_create

    db_host { 'localhost' }
    db_port { 5432 }
    db_name { 'testdb' }
    db_user { 'testuser' }
    db_password { 'testpass' }

    sender_email { 'sender@example.com' }
    sender_password { 'emailpass' }
    receiver_email { 'receiver@example.com' }
    smtp_address { 'smtp.gmail.com' }
    smtp_port { 587 }
    smtp_domain { 'gmail.com' }

    cpu_alert_threshold { 80 }
    query_alert_threshold_minutes { 5 }
    heap_cache_hit_ratio_min { 95 }
    index_cache_hit_ratio_min { 90 }
    table_growth_threshold_percent { 20 }
    alert_cooldown_minutes { 60 }

    log_file { '/tmp/test.log' }
    log_level { 'info' }

    pg_log_path { '/var/log/postgresql' }
    pg_log_file_pattern { 'postgresql-*.log' }

    auto_kill_rogue_processes { false }

    initialize_with do
      # Create a temporary config file for testing
      config_content = {
        'database' => {
          'host' => db_host,
          'port' => db_port,
          'name' => db_name
        },
        'email' => {
          'sender_email' => sender_email,
          'receiver_email' => receiver_email,
          'smtp_address' => smtp_address,
          'smtp_port' => smtp_port,
          'smtp_domain' => smtp_domain
        },
        'thresholds' => {
          'cpu_threshold_percent' => cpu_alert_threshold,
          'query_alert_threshold_minutes' => query_alert_threshold_minutes,
          'heap_cache_hit_ratio_min' => heap_cache_hit_ratio_min,
          'index_cache_hit_ratio_min' => index_cache_hit_ratio_min,
          'table_growth_threshold_percent' => table_growth_threshold_percent
        },
        'cooldown' => {
          'alert_cooldown_minutes' => alert_cooldown_minutes
        },
        'logging' => {
          'log_file' => log_file,
          'log_level' => log_level
        },
        'postgresql_logs' => {
          'path' => pg_log_path,
          'file_pattern' => pg_log_file_pattern
        },
        'features' => {
          'auto_kill_rogue_processes' => auto_kill_rogue_processes
        }
      }

      config_file = Tempfile.new(['test_config', '.yml'])
      config_file.write(config_content.to_yaml)
      config_file.close

      # Set environment variables
      original_env = {}
      %w[PG_USER PG_PASSWORD EMAIL_PASSWORD].each do |var|
        original_env[var] = ENV[var]
        ENV[var] = send(var.downcase.to_sym)
      end

      begin
        config = new(config_file.path)
        config_file.unlink
        config
      ensure
        # Restore environment variables
        original_env.each do |var, value|
          if value.nil?
            ENV.delete(var)
          else
            ENV[var] = value
          end
        end
      end
    end
  end

  factory :invalid_config, class: PgMonitor::Config do
    skip_create

    initialize_with do
      # Don't set required environment variables
      new('/nonexistent/path/config.yml')
    end
  end
end
