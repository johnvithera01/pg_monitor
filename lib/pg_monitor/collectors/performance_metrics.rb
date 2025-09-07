# lib/pg_monitor/collectors/performance_metrics.rb
require_relative 'base_collector'

module PgMonitor
  module Collectors
    class PerformanceMetrics < BaseCollector
      def monitor
        monitor_autovacuum
        monitor_slow_queries
        monitor_index_usage
      end

      private

      def monitor_autovacuum
        result_autovac = execute_query(%Q{
          SELECT
            relname,
            last_autovacuum,
            last_autoanalyze,
            autovacuum_count,
            analyze_count,
            n_dead_tup
          FROM pg_stat_all_tables
          WHERE schemaname = 'public' AND (last_autovacuum IS NULL OR last_autovacuum < NOW() - INTERVAL '7 days')
          and n_dead_tup > 0
          ORDER BY autovacuum_count ASC NULLS FIRST;
        })

        if result_autovac && result_autovac.any?
          add_alert("AVISO: Tabelas com autovacuum inativo ou muito antigo (últimos 5 com tuplas mortas):")
          result_autovac.each do |row|
            add_alert("  Tabela: #{row['relname']}, Último AV: #{row['last_autovacuum'] || 'Nunca'}, Última AA: #{row['last_autoanalyze'] || 'Nunca'}, Tuplas Mortas: #{row['n_dead_tup']}")
          end
        end
      end

      def monitor_slow_queries
        result_slow_queries = execute_query(%Q{
           SELECT
            query,
            calls,
            total_exec_time total_time,
            mean_exec_time mean_time,
            rows
          FROM pg_stat_statements
          ORDER BY total_time DESC
          LIMIT 10;
        })

        if result_slow_queries && result_slow_queries.any?
          add_alert("INFORMAÇÃO: Top 10 Consultas Mais Lentas (total_time):")
          result_slow_queries.each do |row|
            add_alert("  Query: #{row['query'].to_s.strip[0..100]}..., Chamadas: #{row['calls']}, Tempo Total: #{'%.2f' % row['total_time']}ms, Tempo Médio: #{'%.2f' % row['mean_time']}ms, Linhas: #{row['rows']}")
          end
        end
      end

      def monitor_index_usage
        result_unused_idx = execute_query(%Q{
        SELECT
        psu.relname AS table_name,
        psu.indexrelid::regclass AS index_name,
        pg_size_pretty(pg_relation_size(psu.indexrelid)) AS index_size,
        psu.idx_scan AS index_scans
      FROM pg_stat_user_indexes AS psu
      JOIN pg_index AS pi
        ON psu.indexrelid = pi.indexrelid
      WHERE
        psu.idx_scan = 0
        AND pg_relation_size(psu.indexrelid) > 1000 * 1024 * 1024 # Only show indexes larger than 1GB
        AND NOT pi.indisprimary
      ORDER BY
        pg_relation_size(psu.indexrelid) desc
      LIMIT 10;
        })

        if result_unused_idx && result_unused_idx.any?
          add_alert("INFORMAÇÃO: Índices Não Utilizados Encontrados (Top 10 por tamanho, >1GB):")
          result_unused_idx.each do |row|
            add_alert("  Tabela: #{row['table_name']}, Índice: #{row['index_name']}, Tamanho: #{row['index_size']}. Considere remover.")
          end
        end
      end
    end
  end
end
