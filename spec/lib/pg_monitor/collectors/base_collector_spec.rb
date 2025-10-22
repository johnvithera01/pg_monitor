# spec/lib/pg_monitor/collectors/base_collector_spec.rb
require 'spec_helper'

RSpec.describe PgMonitor::Collectors::BaseCollector do
  let(:mock_connection) { instance_double(PgMonitor::Connection) }
  let(:config) { instance_double(PgMonitor::Config) }
  let(:alert_messages) { [] }
  let(:collector) { described_class.new(mock_connection, config, alert_messages) }

  describe '#initialize' do
    it 'sets connection, config, and alert_messages' do
      expect(collector.instance_variable_get(:@connection)).to eq(mock_connection)
      expect(collector.instance_variable_get(:@config)).to eq(config)
      expect(collector.instance_variable_get(:@alert_messages)).to eq(alert_messages)
    end
  end

  describe '#monitor' do
    it 'raises NotImplementedError' do
      expect { collector.monitor }.to raise_error(NotImplementedError, /Subclasses must implement/)
    end
  end

  describe '#add_alert' do
    it 'adds message to alert_messages array' do
      collector.send(:add_alert, 'Test alert message')

      expect(alert_messages).to include('Test alert message')
    end

    it 'adds multiple messages to alert_messages array' do
      collector.send(:add_alert, 'First alert')
      collector.send(:add_alert, 'Second alert')

      expect(alert_messages).to include('First alert', 'Second alert')
    end
  end

  describe '#execute_query' do
    let(:mock_result) { instance_double(PG::Result) }

    before do
      allow(mock_connection).to receive(:execute_query).with('SELECT 1', []).and_return(mock_result)
    end

    it 'delegates to connection execute_query without parameters' do
      result = collector.send(:execute_query, 'SELECT 1')

      expect(mock_connection).to have_received(:execute_query).with('SELECT 1', [])
      expect(result).to eq(mock_result)
    end

    it 'delegates to connection execute_query with parameters' do
      result = collector.send(:execute_query, 'SELECT * FROM users WHERE id = $1', [1])

      expect(mock_connection).to have_received(:execute_query).with('SELECT * FROM users WHERE id = $1', [1])
      expect(result).to eq(mock_result)
    end
  end
end
