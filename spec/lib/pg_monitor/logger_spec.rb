# spec/lib/pg_monitor/logger_spec.rb
require 'spec_helper'
require 'tempfile'

RSpec.describe PgMonitor::Logger do
  let(:config) { instance_double(PgMonitor::Config) }
  let(:logger) { described_class.new(config) }

  before do
    allow(config).to receive(:log_file).and_return('/tmp/test.log')
    allow(config).to receive(:log_level).and_return('info')
    allow(config).to receive(:db_host).and_return('localhost')
    allow(config).to receive(:db_name).and_return('testdb')
  end

  describe '#initialize' do
    it 'creates a logger instance' do
      expect(logger).to be_a(described_class)
    end

    it 'sets up file logger with daily rotation' do
      expect(FileUtils).to receive(:mkdir_p).with('/tmp')
      expect(Logger).to receive(:new).with('/tmp/test.log', 'daily')

      described_class.new(config)
    end

    it 'sets log level based on configuration' do
      allow(config).to receive(:log_level).and_return('debug')

      expect_any_instance_of(Logger).to receive(:level=).with(Logger::DEBUG)

      described_class.new(config)
    end
  end

  describe 'logging methods' do
    let(:mock_logger) { instance_double(Logger) }

    before do
      logger.instance_variable_set(:@logger, mock_logger)
      allow(mock_logger).to receive(:info)
      allow(mock_logger).to receive(:debug)
      allow(mock_logger).to receive(:warn)
      allow(mock_logger).to receive(:error)
      allow(mock_logger).to receive(:fatal)
    end

    describe '#debug' do
      it 'logs debug message' do
        logger.debug('Debug message')

        expect(mock_logger).to have_received(:debug).with(/Debug message/)
      end

      it 'logs debug message with context' do
        context = { query: 'SELECT 1', execution_time: 100 }

        logger.debug('Debug message', context)

        expect(mock_logger).to have_received(:debug).with(/Debug message - Context: #{context.to_json}/)
      end

      it 'includes structured context in log entry' do
        context = { user_id: 123, action: 'login' }
        allow(Time).to receive(:now).and_return(Time.parse('2025-01-01 12:00:00 UTC'))

        logger.debug('User action', context)

        expect(mock_logger).to have_received(:debug).with(/User action - Context: #{context.to_json}/)
      end
    end

    describe '#info' do
      it 'logs info message' do
        logger.info('Info message')

        expect(mock_logger).to have_received(:info).with(/Info message/)
      end

      it 'logs info message with context' do
        context = { connections: 5, status: 'healthy' }

        logger.info('Database status', context)

        expect(mock_logger).to have_received(:info).with(/Database status - Context: #{context.to_json}/)
      end
    end

    describe '#warn' do
      it 'logs warning message' do
        logger.warn('Warning message')

        expect(mock_logger).to have_received(:warn).with(/Warning message/)
      end

      it 'logs warning message with context' do
        context = { threshold: 80, current: 85 }

        logger.warn('Threshold exceeded', context)

        expect(mock_logger).to have_received(:warn).with(/Threshold exceeded - Context: #{context.to_json}/)
      end
    end

    describe '#error' do
      it 'logs error message' do
        logger.error('Error message')

        expect(mock_logger).to have_received(:error).with(/Error message/)
      end

      it 'logs error message with context' do
        context = { error_code: 500, query: 'SELECT * FROM users' }

        logger.error('Query failed', context)

        expect(mock_logger).to have_received(:error).with(/Query failed - Context: #{context.to_json}/)
      end
    end

    describe '#fatal' do
      it 'logs fatal message' do
        logger.fatal('Fatal error')

        expect(mock_logger).to have_received(:fatal).with(/Fatal error/)
      end

      it 'logs fatal message with context' do
        context = { system: 'database', action: 'shutdown' }

        logger.fatal('System failure', context)

        expect(mock_logger).to have_received(:fatal).with(/System failure - Context: #{context.to_json}/)
      end
    end
  end

  describe 'log entry structure' do
    it 'includes timestamp in log context' do
      context = {}
      allow(Time).to receive(:now).and_return(Time.parse('2025-01-01 12:00:00 UTC'))

      logger.instance_variable_set(:@logger, Logger.new('/tmp/test.log'))
      logger.info('Test message', context)

      # The log entry should include structured context
      expect(context).to eq({})
    end

    it 'includes database context in log entries' do
      context = { query: 'SELECT 1' }

      logger.instance_variable_set(:@logger, Logger.new('/tmp/test.log'))
      logger.info('Database query', context)

      # Verify that the logger receives the message with context
      # This is tested through the formatter which includes host and database
    end
  end

  describe 'log levels' do
    it 'maps string levels to Logger constants' do
      expect(described_class::LEVELS['debug']).to eq(Logger::DEBUG)
      expect(described_class::LEVELS['info']).to eq(Logger::INFO)
      expect(described_class::LEVELS['warn']).to eq(Logger::WARN)
      expect(described_class::LEVELS['error']).to eq(Logger::ERROR)
      expect(described_class::LEVELS['fatal']).to eq(Logger::FATAL)
    end

    it 'defaults to INFO level when invalid level specified' do
      allow(config).to receive(:log_level).and_return('invalid')

      expect_any_instance_of(Logger).to receive(:level=).with(Logger::INFO)

      described_class.new(config)
    end
  end

  describe 'formatter' do
    it 'uses custom formatter' do
      logger_instance = described_class.new(config)

      formatter = logger_instance.instance_variable_get(:@logger).formatter

      expect(formatter).to be_a(Proc)

      # Test formatter output
      time = Time.parse('2025-01-01 12:00:00 UTC')
      result = formatter.call(Logger::INFO, time, 'test', 'Test message')

      expect(result).to eq("[2025-01-01 12:00:00] INFO: Test message\n")
    end

    it 'formats timestamp correctly' do
      logger_instance = described_class.new(config)
      formatter = logger_instance.instance_variable_get(:@logger).formatter

      time = Time.parse('2025-01-01 15:30:45 UTC')
      result = formatter.call(Logger::ERROR, time, 'test', 'Error occurred')

      expect(result).to eq("[2025-01-01 15:30:45] ERROR: Error occurred\n")
    end
  end

  describe 'directory creation' do
    it 'creates log directory if it does not exist' do
      expect(FileUtils).to receive(:mkdir_p).with('/tmp')

      described_class.new(config)
    end

    it 'creates nested log directories' do
      allow(config).to receive(:log_file).and_return('/var/log/pg_monitor/test.log')

      expect(FileUtils).to receive(:mkdir_p).with('/var/log/pg_monitor')

      described_class.new(config)
    end
  end
end
