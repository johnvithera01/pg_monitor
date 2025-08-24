# lib/pg_monitor/metrics.rb
require 'prometheus/client'

module PgMonitor
  module Metrics
    REGISTRY = Prometheus::Client.registry

    CHECKS_TOTAL   = REGISTRY.counter(:pgmon_checks_total,   docstring: 'Total de execuções do pg_monitor')
    ALERTS_TOTAL   = REGISTRY.counter(:pgmon_alerts_total,   docstring: 'Alertas gerados')
    FAILED_LOGINS  = REGISTRY.counter(:pgmon_failed_logins_total, docstring: 'Falhas de login detectadas')

    SLOW_QUERIES   = REGISTRY.gauge(:pgmon_slow_queries,     docstring: 'Quantidade de queries lentas')
    IDLE_IN_TX     = REGISTRY.gauge(:pgmon_idle_in_tx,       docstring: 'Sessões idle in transaction')
    OLDEST_XID_AGE = REGISTRY.gauge(:pgmon_oldest_xid_age,   docstring: 'Idade (em tx) do XID mais antigo')
    LAST_RUN_TS    = REGISTRY.gauge(:pgmon_last_run_timestamp, docstring: 'Epoch do último run')

    TABLE_GROWTH   = REGISTRY.gauge(:pgmon_table_growth_pct,
                                    docstring: 'Crescimento percentual por tabela',
                                    labels: [:schema, :table])

    module_function

    def update_from(run_result)
      CHECKS_TOTAL.increment
      SLOW_QUERIES.set((run_result[:slow_queries_count] || 0).to_f)
      IDLE_IN_TX.set((run_result[:idle_in_tx_count] || 0).to_f)
      OLDEST_XID_AGE.set((run_result[:oldest_xid_age] || 0).to_f)

      if run_result[:table_growth].respond_to?(:each)
        run_result[:table_growth].each do |tg|
          TABLE_GROWTH.set({ schema: tg[:schema].to_s, table: tg[:table].to_s },
                           (tg[:growth_pct] || 0).to_f)
        end
      end

      LAST_RUN_TS.set(Time.now.to_i)
    end

    def bump_alerts!(n = 1)
      ALERTS_TOTAL.increment(by: n)
    end

    def bump_failed_logins!(n = 1)
      FAILED_LOGINS.increment(by: n)
    end
  end
end
