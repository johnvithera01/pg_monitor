# spec/lib/pg_monitor/config_spec.rb
require 'spec_helper'
require 'tempfile'
require 'yaml'

RSpec.describe PgMonitor::Config do
  let(:valid_config) do
    {
      'database' => {
        'host' => 'localhost',
        'port' => 5432,
        'name' => 'test_db'
      },
      'email' => {
        'sender_email' => 'test@example.com',
        'receiver_email' => 'admin@example.com',
        'smtp_address' => 'smtp.gmail.com',
        'smtp_port' => 587,
        'smtp_domain' => 'gmail.com'
      },
      'thresholds' => {
        'cpu_threshold_percent' => 80,
        'heap_cache_hit_ratio_min' => 95,
        'index_cache_hit_ratio_min' => 90,
        'query_alert_threshold_minutes' => 5,
        'alert_cooldown_minutes' => 60
      },
      'cooldown' => {
        'alert_cooldown_minutes' => 60,
        'last_alert_file' => '/tmp/test_alerts.json',
        'last_deadlock_file' => '/tmp/test_deadlock.json'
      },
      'logging' => {
        'log_file' => '/tmp/test.log',
        'log_level' => 'info'
      },
      'postgresql_logs' => {
        'path' => '/tmp',
        'file_pattern' => '*.log'
      },
      'features' => {
        'auto_kill_rogue_processes' => false
      }
    }
  end

  let(:config_file) do
    file = Tempfile.new(['config', '.yml'])
    file.write(valid_config.to_yaml)
    file.close
    file
  end

  before do
    ENV['PG_USER'] = 'test_user'
    ENV['PG_PASSWORD'] = 'test_password'
    ENV['EMAIL_PASSWORD'] = 'test_email_password'
  end

  after do
    config_file.unlink
    ENV.delete('PG_USER')
    ENV.delete('PG_PASSWORD')
    ENV.delete('EMAIL_PASSWORD')
  end

  describe '#initialize' do
    context 'with valid configuration' do
      it 'loads configuration successfully' do
        config = described_class.new(config_file.path)
        
        expect(config.db_host).to eq('localhost')
        expect(config.db_port).to eq(5432)
        expect(config.db_name).to eq('test_db')
        expect(config.db_user).to eq('test_user')
        expect(config.db_password).to eq('test_password')
      end
    end

    context 'with missing environment variables' do
      before do
        ENV.delete('PG_USER')
      end

      it 'raises ConfigurationError' do
        expect {
          described_class.new(config_file.path)
        }.to raise_error(PgMonitor::ConfigurationError, /Missing required environment variables/)
      end
    end

    context 'with invalid thresholds' do
      before do
        valid_config['thresholds']['cpu_threshold_percent'] = 150
        File.write(config_file.path, valid_config.to_yaml)
      end

      it 'raises ConfigurationError for invalid CPU threshold' do
        expect {
          described_class.new(config_file.path)
        }.to raise_error(PgMonitor::ConfigurationError)
      end
    end

    context 'with missing config file' do
      it 'raises ConfigurationError' do
        expect {
          described_class.new('/nonexistent/config.yml')
        }.to raise_error(PgMonitor::ConfigurationError, /Configuration file not found/)
      end
    end
  end

  describe '#valid?' do
    it 'returns true for valid configuration' do
      config = described_class.new(config_file.path)
      expect(config).to be_valid
    end
  end
end
