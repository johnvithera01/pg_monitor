# spec/lib/pg_monitor/metrics_spec.rb
require 'spec_helper'

RSpec.describe PgMonitor::Metrics do
  describe 'registry and counters' do
    it 'defines CHECKS_TOTAL counter' do
      expect(described_class::CHECKS_TOTAL).to be_a(Prometheus::Client::Counter)
      expect(described_class::CHECKS_TOTAL.name).to eq(:pgmon_checks_total)
    end

    it 'defines ALERTS_TOTAL counter' do
      expect(described_class::ALERTS_TOTAL).to be_a(Prometheus::Client::Counter)
      expect(described_class::ALERTS_TOTAL.name).to eq(:pgmon_alerts_total)
    end

    it 'defines FAILED_LOGINS counter' do
      expect(described_class::FAILED_LOGINS).to be_a(Prometheus::Client::Counter)
      expect(described_class::FAILED_LOGINS.name).to eq(:pgmon_failed_logins_total)
    end

    it 'defines SLOW_QUERIES gauge' do
      expect(described_class::SLOW_QUERIES).to be_a(Prometheus::Client::Gauge)
      expect(described_class::SLOW_QUERIES.name).to eq(:pgmon_slow_queries)
    end

    it 'defines IDLE_IN_TX gauge' do
      expect(described_class::IDLE_IN_TX).to be_a(Prometheus::Client::Gauge)
      expect(described_class::IDLE_IN_TX.name).to eq(:pgmon_idle_in_tx)
    end

    it 'defines OLDEST_XID_AGE gauge' do
      expect(described_class::OLDEST_XID_AGE).to be_a(Prometheus::Client::Gauge)
      expect(described_class::OLDEST_XID_AGE.name).to eq(:pgmon_oldest_xid_age)
    end

    it 'defines TABLE_GROWTH gauge with labels' do
      expect(described_class::TABLE_GROWTH).to be_a(Prometheus::Client::Gauge)
      expect(described_class::TABLE_GROWTH.name).to eq(:pgmon_table_growth_pct)
    end
  end

  describe '#update_from' do
    let(:run_result) do
      {
        slow_queries_count: 5,
        idle_in_tx_count: 3,
        oldest_xid_age: 1000000,
        table_growth: [
          { schema: 'public', table: 'users', growth_pct: 15.5 },
          { schema: 'public', table: 'orders', growth_pct: 8.2 }
        ]
      }
    end

    before do
      # Reset metrics before each test
      described_class::CHECKS_TOTAL.reset
      described_class::SLOW_QUERIES.reset
      described_class::IDLE_IN_TX.reset
      described_class::OLDEST_XID_AGE.reset
      described_class::TABLE_GROWTH.reset
    end

    it 'increments checks total' do
      expect { described_class.update_from(run_result) }
        .to change { described_class::CHECKS_TOTAL.get }
        .by(1)
    end

    it 'sets slow queries count' do
      described_class.update_from(run_result)

      expect(described_class::SLOW_QUERIES.get).to eq(5.0)
    end

    it 'sets idle in transaction count' do
      described_class.update_from(run_result)

      expect(described_class::IDLE_IN_TX.get).to eq(3.0)
    end

    it 'sets oldest xid age' do
      described_class.update_from(run_result)

      expect(described_class::OLDEST_XID_AGE.get).to eq(1000000.0)
    end

    it 'sets table growth metrics with labels' do
      described_class.update_from(run_result)

      expect(described_class::TABLE_GROWTH.get(schema: 'public', table: 'users')).to eq(15.5)
      expect(described_class::TABLE_GROWTH.get(schema: 'public', table: 'orders')).to eq(8.2)
    end

    it 'handles missing values gracefully' do
      empty_result = {}

      expect { described_class.update_from(empty_result) }
        .to change { described_class::CHECKS_TOTAL.get }
        .by(1)

      expect(described_class::SLOW_QUERIES.get).to eq(0.0)
      expect(described_class::IDLE_IN_TX.get).to eq(0.0)
      expect(described_class::OLDEST_XID_AGE.get).to eq(0.0)
    end

    it 'handles nil values gracefully' do
      nil_result = {
        slow_queries_count: nil,
        idle_in_tx_count: nil,
        oldest_xid_age: nil,
        table_growth: nil
      }

      expect { described_class.update_from(nil_result) }
        .to change { described_class::CHECKS_TOTAL.get }
        .by(1)

      expect(described_class::SLOW_QUERIES.get).to eq(0.0)
      expect(described_class::IDLE_IN_TX.get).to eq(0.0)
      expect(described_class::OLDEST_XID_AGE.get).to eq(0.0)
    end

    it 'handles empty table growth array' do
      result_with_empty_growth = run_result.merge(table_growth: [])

      expect { described_class.update_from(result_with_empty_growth) }
        .to change { described_class::CHECKS_TOTAL.get }
        .by(1)

      expect(described_class::TABLE_GROWTH.get(schema: 'public', table: 'users')).to eq(0.0)
    end

    it 'handles non-array table growth' do
      result_with_invalid_growth = run_result.merge(table_growth: 'invalid')

      expect { described_class.update_from(result_with_invalid_growth) }
        .to change { described_class::CHECKS_TOTAL.get }
        .by(1)

      # Should not crash and should handle gracefully
      expect(described_class::SLOW_QUERIES.get).to eq(5.0)
    end
  end

  describe '#bump_alerts!' do
    before do
      described_class::ALERTS_TOTAL.reset
    end

    it 'increments alerts counter by 1' do
      expect { described_class.bump_alerts! }
        .to change { described_class::ALERTS_TOTAL.get }
        .by(1)
    end

    it 'increments alerts counter by specified amount' do
      expect { described_class.bump_alerts!(3) }
        .to change { described_class::ALERTS_TOTAL.get }
        .by(3)
    end

    it 'increments alerts counter multiple times' do
      expect {
        described_class.bump_alerts!
        described_class.bump_alerts!
        described_class.bump_alerts!
      }.to change { described_class::ALERTS_TOTAL.get }
        .by(3)
    end
  end

  describe '#bump_failed_logins!' do
    before do
      described_class::FAILED_LOGINS.reset
    end

    it 'increments failed logins counter by 1' do
      expect { described_class.bump_failed_logins! }
        .to change { described_class::FAILED_LOGINS.get }
        .by(1)
    end

    it 'increments failed logins counter by specified amount' do
      expect { described_class.bump_failed_logins!(5) }
        .to change { described_class::FAILED_LOGINS.get }
        .by(5)
    end

    it 'increments failed logins counter multiple times' do
      expect {
        described_class.bump_failed_logins!
        described_class.bump_failed_logins!(2)
        described_class.bump_failed_logins!
      }.to change { described_class::FAILED_LOGINS.get }
        .by(4)
    end
  end

  describe 'metric documentation' do
    it 'includes docstrings for all metrics' do
      expect(described_class::CHECKS_TOTAL.docstring).to eq('Total de execuções do pg_monitor')
      expect(described_class::ALERTS_TOTAL.docstring).to eq('Alertas gerados')
      expect(described_class::FAILED_LOGINS.docstring).to eq('Falhas de login detectadas')
      expect(described_class::SLOW_QUERIES.docstring).to eq('Quantidade de queries lentas')
      expect(described_class::IDLE_IN_TX.docstring).to eq('Sessões idle in transaction')
      expect(described_class::OLDEST_XID_AGE.docstring).to eq('Idade (em tx) do XID mais antigo')
    end
  end

  describe 'metric types' do
    it 'uses counter for cumulative metrics' do
      expect(described_class::CHECKS_TOTAL).to be_a(Prometheus::Client::Counter)
      expect(described_class::ALERTS_TOTAL).to be_a(Prometheus::Client::Counter)
      expect(described_class::FAILED_LOGINS).to be_a(Prometheus::Client::Counter)
    end

    it 'uses gauge for instantaneous metrics' do
      expect(described_class::SLOW_QUERIES).to be_a(Prometheus::Client::Gauge)
      expect(described_class::IDLE_IN_TX).to be_a(Prometheus::Client::Gauge)
      expect(described_class::OLDEST_XID_AGE).to be_a(Prometheus::Client::Gauge)
    end

    it 'uses gauge with labels for table-specific metrics' do
      expect(described_class::TABLE_GROWTH).to be_a(Prometheus::Client::Gauge)
      expect(described_class::TABLE_GROWTH.labels).to eq([:schema, :table])
    end
  end

  describe 'registry integration' do
    it 'registers all metrics in the global registry' do
      registry = Prometheus::Client.registry

      expect(registry.metrics.keys).to include(:pgmon_checks_total)
      expect(registry.metrics.keys).to include(:pgmon_alerts_total)
      expect(registry.metrics.keys).to include(:pgmon_failed_logins_total)
      expect(registry.metrics.keys).to include(:pgmon_slow_queries)
      expect(registry.metrics.keys).to include(:pgmon_idle_in_tx)
      expect(registry.metrics.keys).to include(:pgmon_oldest_xid_age)
      expect(registry.metrics.keys).to include(:pgmon_table_growth_pct)
    end

    it 'uses the shared registry' do
      expect(described_class::REGISTRY).to eq(Prometheus::Client.registry)
    end
  end
end
