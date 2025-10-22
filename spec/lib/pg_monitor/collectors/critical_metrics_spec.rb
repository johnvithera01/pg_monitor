# spec/lib/pg_monitor/collectors/critical_metrics_spec.rb
require 'spec_helper'

RSpec.describe PgMonitor::Collectors::CriticalMetrics do
  let(:mock_connection) { instance_double(PgMonitor::Connection) }
  let(:config) { instance_double(PgMonitor::Config) }
  let(:alert_messages) { [] }
  let(:collector) { described_class.new(mock_connection, config, alert_messages) }

  before do
    allow(config).to receive(:cpu_alert_threshold).and_return(80)
    allow(config).to receive(:query_alert_threshold_minutes).and_return(5)
    allow(config).to receive(:heap_cache_hit_ratio_min).and_return(95)
    allow(config).to receive(:index_cache_hit_ratio_min).and_return(90)
    allow(config).to receive(:table_growth_threshold_percent).and_return(20)
  end

  describe '#monitor' do
    it 'calls all monitoring methods' do
      allow(collector).to receive(:monitor_cpu)
      allow(collector).to receive(:monitor_active_connections)
      allow(collector).to receive(:monitor_long_transactions)
      allow(collector).to receive(:monitor_active_locks)
      allow(collector).to receive(:monitor_xid_wraparound)
      allow(collector).to receive(:monitor_io)
      allow(collector).to receive(:monitor_long_running_queries)
      allow(collector).to receive(:monitor_cache_hit_ratio)

      collector.monitor

      expect(collector).to have_received(:monitor_cpu)
      expect(collector).to have_received(:monitor_active_connections)
      expect(collector).to have_received(:monitor_long_transactions)
      expect(collector).to have_received(:monitor_active_locks)
      expect(collector).to have_received(:monitor_xid_wraparound)
      expect(collector).to have_received(:monitor_io)
      expect(collector).to have_received(:monitor_long_running_queries)
      expect(collector).to have_received(:monitor_cache_hit_ratio)
    end
  end

  describe '#monitor_cpu' do
    context 'when mpstat command succeeds' do
      before do
        allow(collector).to receive(:`).with('mpstat -u ALL 1 1 2>/dev/null').and_return(
          "Linux 5.4.0-74-generic (hostname) \t\tdomingo 30 de mayo de 2021 \t_x86_64_\t(8 CPU)\n\n" +
          "12:00:00     CPU    %usr   %nice    %sys   %iowait    %irq   %soft  %steal  %guest  %gnice   %idle\n" +
          "12:00:01     all    2.00    0.00    3.00     1.00    0.00    0.00    0.00    0.00    0.00   94.00\n" +
          "Average:     all    2.00    0.00    3.00     1.00    0.00    0.00    0.00    0.00    0.00   94.00"
        )
      end

      it 'does not alert when CPU usage is below threshold' do
        allow(config).to receive(:cpu_alert_threshold).and_return(80)

        collector.send(:monitor_cpu)

        expect(alert_messages).to be_empty
      end

      it 'alerts when CPU usage is above threshold' do
        allow(config).to receive(:cpu_alert_threshold).and_return(5)

        collector.send(:monitor_cpu)

        expect(alert_messages).to include(/Alto uso de CPU detectado/)
      end
    end

    context 'when mpstat command fails' do
      before do
        allow(collector).to receive(:`).with('mpstat -u ALL 1 1 2>/dev/null').and_return('')
      end

      it 'does not alert when mpstat output is empty' do
        collector.send(:monitor_cpu)

        expect(alert_messages).to be_empty
      end
    end

    context 'when mpstat command is not found' do
      before do
        allow(collector).to receive(:`).with('mpstat -u ALL 1 1 2>/dev/null').and_raise(Errno::ENOENT)
      end

      it 'alerts about missing mpstat command' do
        collector.send(:monitor_cpu)

        expect(alert_messages).to include(/Comando 'mpstat' não encontrado/)
      end
    end

    context 'when mpstat command raises other errors' do
      before do
        allow(collector).to receive(:`).with('mpstat -u ALL 1 1 2>/dev/null').and_raise(StandardError.new('Command failed'))
      end

      it 'alerts about mpstat error' do
        collector.send(:monitor_cpu)

        expect(alert_messages).to include(/Erro ao executar mpstat/)
      end
    end
  end

  describe '#monitor_active_connections' do
    context 'when query succeeds' do
      before do
        mock_result = instance_double(PG::Result)
        allow(mock_result).to receive(:first).and_return({ 'total_connections' => '45' })
        allow(mock_connection).to receive(:execute_query).with(/SELECT count/).and_return(mock_result)

        mock_max_result = instance_double(PG::Result)
        allow(mock_max_result).to receive(:first).and_return({ 'max_connections' => '100' })
        allow(mock_connection).to receive(:execute_query).with(/SHOW max_connections/).and_return(mock_max_result)
      end

      it 'does not alert when connections are below 90% of max' do
        collector.send(:monitor_active_connections)

        expect(alert_messages).to be_empty
      end

      it 'alerts when connections are above 90% of max' do
        # 95 connections out of 100 = 95% > 90%
        allow(mock_connection).to receive(:execute_query).with(/SELECT count/).and_return(
          instance_double(PG::Result, first: { 'total_connections' => '95' })
        )

        collector.send(:monitor_active_connections)

        expect(alert_messages).to include(/Conexões.*estão muito próximas do limite máximo/)
      end
    end

    context 'when query fails' do
      before do
        allow(mock_connection).to receive(:execute_query).and_return(nil)
      end

      it 'does not alert when query fails' do
        collector.send(:monitor_active_connections)

        expect(alert_messages).to be_empty
      end
    end
  end

  describe '#monitor_long_transactions' do
    context 'when long transactions are found' do
      before do
        mock_result = instance_double(PG::Result)
        allow(mock_result).to receive(:any?).and_return(true)
        allow(mock_result).to receive(:each).and_yield(
          'pid' => '1234',
          'usename' => 'testuser',
          'application_name' => 'testapp',
          'query' => 'SELECT * FROM large_table WHERE condition = 1',
          'query_duration' => '00:05:30'
        )

        allow(mock_connection).to receive(:execute_query).with(/pg_stat_activity.*WHERE.*age.*3 minutes/).and_return(mock_result)
      end

      it 'alerts about long transactions' do
        collector.send(:monitor_long_transactions)

        expect(alert_messages).to include(/Transações Muito Longas.*Detectadas/)
        expect(alert_messages).to include(/PID: 1234/)
      end
    end

    context 'when no long transactions are found' do
      before do
        mock_result = instance_double(PG::Result)
        allow(mock_result).to receive(:any?).and_return(false)
        allow(mock_connection).to receive(:execute_query).and_return(mock_result)
      end

      it 'does not alert' do
        collector.send(:monitor_long_transactions)

        expect(alert_messages).to be_empty
      end
    end
  end

  describe '#monitor_active_locks' do
    context 'when active locks are found' do
      before do
        mock_result = instance_double(PG::Result)
        allow(mock_result).to receive(:any?).and_return(true)
        allow(mock_result).to receive(:each).and_yield(
          'blocking_pid' => '1234',
          'blocking_user' => 'user1',
          'blocked_pid' => '5678',
          'blocked_user' => 'user2',
          'blocked_query' => 'UPDATE table SET col = 1',
          'blocked_duration' => '00:01:30'
        )

        allow(mock_connection).to receive(:execute_query).with(/pg_locks.*WHERE.*30 seconds/).and_return(mock_result)
      end

      it 'alerts about active locks' do
        collector.send(:monitor_active_locks)

        expect(alert_messages).to include(/Bloqueios Ativos Persistentes Detectados/)
        expect(alert_messages).to include(/Bloqueado.*PID: 5678/)
      end
    end

    context 'when no active locks are found' do
      before do
        mock_result = instance_double(PG::Result)
        allow(mock_result).to receive(:any?).and_return(false)
        allow(mock_connection).to receive(:execute_query).and_return(mock_result)
      end

      it 'does not alert' do
        collector.send(:monitor_active_locks)

        expect(alert_messages).to be_empty
      end
    end
  end

  describe '#monitor_xid_wraparound' do
    before do
      allow(mock_connection).to receive(:execute_query).with(/SELECT.*age.*FROM.*pg_control_checkpoint/)
    end

    it 'executes xid wraparound query' do
      collector.send(:monitor_xid_wraparound)

      expect(mock_connection).to have_received(:execute_query).with(/SELECT.*age.*FROM.*pg_control_checkpoint/)
    end
  end

  describe '#monitor_io' do
    before do
      allow(collector).to receive(:`).with('iostat -x 1 2 2>/dev/null')
    end

    it 'executes iostat command' do
      collector.send(:monitor_io)

      expect(collector).to have_received(:`).with('iostat -x 1 2 2>/dev/null')
    end
  end

  describe '#monitor_long_running_queries' do
    before do
      allow(mock_connection).to receive(:execute_query).with(/pg_stat_activity.*state.*active/)
    end

    it 'executes long running queries query' do
      collector.send(:monitor_long_running_queries)

      expect(mock_connection).to have_received(:execute_query).with(/pg_stat_activity.*state.*active/)
    end
  end

  describe '#monitor_cache_hit_ratio' do
    before do
      allow(mock_connection).to receive(:execute_query).with(/pg_stat_database/)
    end

    it 'executes cache hit ratio query' do
      collector.send(:monitor_cache_hit_ratio)

      expect(mock_connection).to have_received(:execute_query).with(/pg_stat_database/)
    end
  end
end
