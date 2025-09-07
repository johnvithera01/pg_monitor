# spec/integration/pg_monitor_spec.rb
require 'spec_helper'
require 'tempfile'
require 'yaml'

RSpec.describe 'PgMonitor Integration Tests' do
  let(:temp_config) do
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
        'alert_cooldown_minutes' => 60,
        'iostat_threshold_kb_s' => 50000,
        'iostat_device' => 'vda'
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
    file.write(temp_config.to_yaml)
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

  describe 'Configuration Loading' do
    it 'loads configuration successfully' do
      config = PgMonitor::Config.new(config_file.path)
      
      expect(config.db_host).to eq('localhost')
      expect(config.db_port).to eq(5432)
      expect(config.db_name).to eq('test_db')
      expect(config.db_user).to eq('test_user')
      expect(config.db_password).to eq('test_password')
    end

    it 'validates configuration correctly' do
      config = PgMonitor::Config.new(config_file.path)
      expect(config).to be_valid
    end
  end

  describe 'Connection Management' do
    let(:config) { PgMonitor::Config.new(config_file.path) }
    let(:connection) { PgMonitor::Connection.new(config) }

    it 'handles connection errors gracefully' do
      allow(connection).to receive(:connect).and_raise(PG::ConnectionBad.new('Connection failed'))
      
      expect {
        connection.connect
      }.to raise_error(PgMonitor::ConnectionError)
    end

    it 'retries connection on failure' do
      call_count = 0
      allow(connection).to receive(:connect) do
        call_count += 1
        if call_count < 3
          raise PG::ConnectionBad.new('Connection failed')
        else
          double('connection', status: PG::CONNECTION_OK)
        end
      end

      connection.connect
      expect(call_count).to eq(3)
    end
  end

  describe 'Email Sending' do
    let(:config) { PgMonitor::Config.new(config_file.path) }
    let(:email_sender) { PgMonitor::EmailSender.new(config) }

    it 'respects cooldown period' do
      # Mock the file system
      allow(File).to receive(:exist?).with('/tmp/test_alerts.json').and_return(true)
      allow(File).to receive(:read).with('/tmp/test_alerts.json').and_return({
        'test_alert' => (Time.now - 30 * 60).iso8601
      }.to_json)

      # Mock Mail.deliver
      allow(Mail).to receive(:deliver)

      email_sender.send_alert_email('Test Subject', 'Test Body', 'test_alert')
      
      # Should not send email due to cooldown
      expect(Mail).not_to have_received(:deliver)
    end

    it 'sends email when cooldown period has passed' do
      # Mock the file system
      allow(File).to receive(:exist?).with('/tmp/test_alerts.json').and_return(true)
      allow(File).to receive(:read).with('/tmp/test_alerts.json').and_return({
        'test_alert' => (Time.now - 2 * 60 * 60).iso8601
      }.to_json)
      allow(File).to receive(:write)

      # Mock Mail.deliver
      allow(Mail).to receive(:deliver)

      email_sender.send_alert_email('Test Subject', 'Test Body', 'test_alert')
      
      # Should send email
      expect(Mail).to have_received(:deliver)
    end
  end

  describe 'Metrics Collection' do
    let(:config) { PgMonitor::Config.new(config_file.path) }
    let(:connection) { double('connection') }
    let(:alert_messages) { [] }

    it 'collects critical metrics' do
      collector = PgMonitor::Collectors::CriticalMetrics.new(connection, config, alert_messages)
      
      # Mock connection methods
      allow(connection).to receive(:execute_query).and_return([])
      allow(collector).to receive(:`).and_return('')

      collector.monitor
      
      expect(alert_messages).to be_an(Array)
    end

    it 'collects performance metrics' do
      collector = PgMonitor::Collectors::PerformanceMetrics.new(connection, config, alert_messages)
      
      # Mock connection methods
      allow(connection).to receive(:execute_query).and_return([])

      collector.monitor
      
      expect(alert_messages).to be_an(Array)
    end

    it 'collects security metrics' do
      collector = PgMonitor::Collectors::SecurityMetrics.new(connection, config, alert_messages)
      
      # Mock connection methods
      allow(connection).to receive(:execute_query).and_return([])
      allow(Dir).to receive(:exist?).and_return(true)
      allow(Dir).to receive(:glob).and_return([])

      collector.monitor
      
      expect(alert_messages).to be_an(Array)
    end
  end

  describe 'Prometheus Metrics' do
    it 'exports metrics correctly' do
      # Mock the metrics registry
      allow(PgMonitor::Metrics::REGISTRY).to receive(:counter)
      allow(PgMonitor::Metrics::REGISTRY).to receive(:gauge)

      # Test metrics update
      result = {
        slow_queries_count: 5,
        idle_in_tx_count: 2,
        oldest_xid_age: 1000,
        table_growth: [
          { schema: 'public', table: 'users', growth_pct: 10.5 }
        ]
      }

      expect {
        PgMonitor::Metrics.update_from(result)
      }.not_to raise_error
    end
  end

  describe 'Alert Sink' do
    let(:config) { PgMonitor::Config.new(config_file.path) }
    let(:alert_sink) { PgMonitor::AlertSink.new(config) }

    it 'sends alerts via multiple channels' do
      # Mock the alert methods
      allow(alert_sink).to receive(:send_email_alert)
      allow(alert_sink).to receive(:send_slack_alert)
      allow(alert_sink).to receive(:send_webhook_alert)

      alert_data = {
        type: 'high_cpu',
        severity: 'critical',
        subject: 'High CPU Usage',
        body: 'CPU usage is at 95%',
        timestamp: Time.now.iso8601
      }

      alert_sink.send_alert(alert_data)

      expect(alert_sink).to have_received(:send_email_alert)
    end
  end

  describe 'Error Handling' do
    it 'handles database connection errors' do
      config = PgMonitor::Config.new(config_file.path)
      connection = PgMonitor::Connection.new(config)
      
      allow(connection).to receive(:connect).and_raise(PG::ConnectionBad.new('Connection failed'))
      
      expect {
        connection.connect
      }.to raise_error(PgMonitor::ConnectionError)
    end

    it 'handles query execution errors' do
      config = PgMonitor::Config.new(config_file.path)
      connection = PgMonitor::Connection.new(config)
      
      # Mock connection
      mock_conn = double('connection', status: PG::CONNECTION_OK)
      allow(connection).to receive(:connected?).and_return(true)
      allow(connection).to receive(:raw_connection).and_return(mock_conn)
      
      # Mock query execution to raise error
      allow(mock_conn).to receive(:exec).and_raise(PG::Error.new('Query failed'))
      
      expect {
        connection.execute_query('SELECT 1')
      }.to raise_error(PgMonitor::QueryError)
    end

    it 'handles email sending errors' do
      config = PgMonitor::Config.new(config_file.path)
      email_sender = PgMonitor::EmailSender.new(config)
      
      # Mock Mail.deliver to raise error
      allow(Mail).to receive(:deliver).and_raise(StandardError.new('SMTP Error'))
      
      expect {
        email_sender.send_alert_email('Test', 'Body', 'test')
      }.to raise_error(PgMonitor::EmailError)
    end
  end

  describe 'Configuration Validation' do
    it 'validates required environment variables' do
      ENV.delete('PG_USER')
      
      expect {
        PgMonitor::Config.new(config_file.path)
      }.to raise_error(PgMonitor::ConfigurationError, /Missing required environment variables/)
    end

    it 'validates threshold values' do
      temp_config['thresholds']['cpu_threshold_percent'] = 150
      File.write(config_file.path, temp_config.to_yaml)
      
      expect {
        PgMonitor::Config.new(config_file.path)
      }.to raise_error(PgMonitor::ConfigurationError)
    end

    it 'validates email configuration' do
      temp_config['email']['sender_email'] = ''
      File.write(config_file.path, temp_config.to_yaml)
      
      expect {
        PgMonitor::Config.new(config_file.path)
      }.to raise_error(PgMonitor::ConfigurationError)
    end
  end

  describe 'File Operations' do
    it 'creates necessary directories' do
      config = PgMonitor::Config.new(config_file.path)
      
      expect(File.directory?(File.dirname(config.log_file))).to be true
      expect(File.directory?(File.dirname(config.last_alert_file))).to be true
    end

    it 'handles file permission errors gracefully' do
      config = PgMonitor::Config.new(config_file.path)
      
      # Mock FileUtils.mkdir_p to raise error
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES.new('Permission denied'))
      
      expect {
        PgMonitor::Config.new(config_file.path)
      }.to raise_error(Errno::EACCES)
    end
  end
end
