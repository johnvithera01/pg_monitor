# lib/pg_monitor/collectors/critical_metrics.rb
require_relative 'base_collector'

module PgMonitor
  module Collectors
    class CriticalMetrics < BaseCollector
      def monitor
        monitor_cpu
        monitor_active_connections
        monitor_long_transactions
        monitor_active_locks
        monitor_xid_wraparound
        monitor_io
        monitor_long_running_queries
        monitor_cache_hit_ratio
      end

      private

      def monitor_cpu
        begin
          mpstat_output = `mpstat -u ALL 1 1 2>/dev/null`
          if mpstat_output && !mpstat_output.empty?
            lines = mpstat_output.split("\n")
            cpu_line = lines.reverse.find { |line| line.strip.start_with?('Average:') && line.include?('all') }

            if cpu_line
              parts = cpu_line.split(/\s+/)
              idle_percent_index = parts.index('%idle')
              if idle_percent_index
                idle_cpu_percent = parts[idle_percent_index + 1].to_f
                used_cpu_percent = 100.0 - idle_cpu_percent

                if used_cpu_percent > @config.cpu_alert_threshold
                  add_alert("ALERTA: Alto uso de CPU detectado! Uso total: #{'%.2f' % used_cpu_percent}% (Limiar: #{@config.cpu_alert_threshold}%).")
                end
              end
            end
          end
        rescue Errno::ENOENT
          add_alert("ERRO: Comando 'mpstat' não encontrado. Certifique-se de que o pacote 'sysstat' está instalado.")
        rescue StandardError => e
          add_alert("Erro ao executar mpstat: #{e.message}")
        end
      end

      def monitor_active_connections
        result_conn = execute_query("SELECT count(*) AS total_connections FROM pg_stat_activity;")
        if result_conn
          total_connections = result_conn.first['total_connections'].to_i
          result_max = execute_query("SHOW max_connections;")
          if result_max
            max_connections = result_max.first['max_connections'].to_i
            if total_connections >= max_connections * 0.9
              add_alert("ALERTA CRÍTICO: Conexões (#{total_connections}) estão muito próximas do limite máximo (#{max_connections})!")
            end
          end
        end
      end

      def monitor_long_transactions
        result_long_tx = execute_query(%Q{
          SELECT
            pid, usename, application_name, query,
            age(now(), query_start) AS query_duration
          FROM pg_stat_activity
          WHERE state IN ('active', 'idle in transaction') AND age(now(), query_start) > INTERVAL '3 minutes'
          ORDER BY query_duration DESC;
        })

        if result_long_tx && result_long_tx.any?
          add_alert("ALERTA CRÍTICO: Transações Muito Longas/Inativas Detectadas (>= 3 min):")
          result_long_tx.each do |row|
            add_alert("  PID: #{row['pid']}, Usuário: #{row['usename']}, Duração: #{row['query_duration']}, Query: #{row['query'].strip[0..100]}...")
          end
        end
      end

      def monitor_active_locks
        result_locks = execute_query(%Q{
          SELECT
              blocking_activity.pid AS blocking_pid,
              blocking_activity.usename AS blocking_user,
              blocked_activity.pid AS blocked_pid,
              blocked_activity.usename AS blocked_user,
              blocked_activity.query AS blocked_query,
              age(now(), blocked_activity.query_start) AS blocked_duration
          FROM pg_catalog.pg_locks blocked_locks
          JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
          JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype 
          JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
          WHERE NOT blocked_locks.granted AND age(now(), blocked_activity.query_start) > INTERVAL '30 seconds';
        })

        if result_locks && result_locks.any?
          add_alert("ALERTA CRÍTICO: Bloqueios Ativos Persistentes Detectados (>= 30s):")
          result_locks.each do |row|
            add_alert("  Bloqueado (PID: #{row['blocked_pid']}, User: #{row['blocked_user']}): #{row['blocked_query'].to_s.strip[0..100]}... (Duração: #{row['blocked_duration']})")
          end
        end
      end

      def monitor_xid_wraparound
        result_xid = execute_query(%Q{
          SELECT
            datname,
            age(datfrozenxid) AS xid_age,
            (SELECT setting::bigint FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS freeze_max_age
          FROM pg_database
          ORDER BY xid_age DESC;
        })

        if result_xid && result_xid.any?
          result_xid.each do |row|
            xid_age = row['xid_age'].to_i
            freeze_max_age = row['freeze_max_age'].to_i
            if xid_age > (freeze_max_age * 0.9).to_i
              add_alert("ALERTA CRÍTICO: ID de transação para '#{row['datname']}' está MUITO PRÓXIMO do limite de wraparound! Idade atual: #{xid_age} (Limite: #{freeze_max_age}).")
            end
          end
        end
      end

      def monitor_io
        begin
          iostat_output = `iostat -k #{@config.iostat_device} 1 2 2>/dev/null`
          if iostat_output && !iostat_output.empty?
            lines = iostat_output.split("\n")
            disk_line = lines.reverse.find { |line| line.strip.start_with?(@config.iostat_device) }

            if disk_line
              parts = disk_line.split(/\s+/)
              rkbs_idx = parts.index(@config.iostat_device) + 3 if parts.index(@config.iostat_device)
              wkbs_idx = parts.index(@config.iostat_device) + 4 if parts.index(@config.iostat_device)

              rkbs = (rkbs_idx && parts[rkbs_idx]) ? parts[rkbs_idx].to_f : 0.0
              wkbs = (wkbs_idx && parts[wkbs_idx]) ? parts[wkbs_idx].to_f : 0.0

              total_kb_s = rkbs + wkbs

              if total_kb_s > @config.iostat_threshold_kb_s
                add_alert("ALERTA: Alto I/O de disco em '#{@config.iostat_device}' detectado! Total: #{'%.2f' % (total_kb_s / 1024)} MB/s (Leitura: #{'%.2f' % (rkbs / 1024)} MB/s, Escrita: #{'%.2f' % (wkbs / 1024)} MB/s).")
              end
            end
          end
        rescue Errno::ENOENT
          add_alert("ERRO: Comando 'iostat' não encontrado. Certifique-se de que o pacote 'sysstat' está instalado.")
        rescue StandardError => e
          add_alert("Erro ao executar iostat: #{e.message}")
        end
      end

      def monitor_long_running_queries
        long_running_queries = execute_query(%Q{
          SELECT
            pid, usename, application_name, client_addr, query,
            EXTRACT(EPOCH FROM (NOW() - query_start)) AS duration_seconds
          FROM pg_stat_activity
          WHERE state = 'active'
            AND usename != 'repack'
            AND application_name NOT LIKE '%pg_repack%'
            AND backend_type = 'client backend'
            AND NOW() - query_start > INTERVAL '#{@config.query_alert_threshold_minutes} minutes'
          ORDER BY duration_seconds DESC;
        })

        if long_running_queries && long_running_queries.any?
          add_alert("ALERTA CRÍTICO: Consultas rodando há mais de #{@config.query_alert_threshold_minutes} minutos:")
          long_running_queries.each do |row|
            duration_minutes = row['duration_seconds'].to_i / 60
            query_info = "  PID: #{row['pid']}, Usuário: #{row['usename']}, App: #{row['application_name']}, Cliente: #{row['client_addr']}, Duração: #{duration_minutes} min, Query: #{row['query'].to_s.strip[0..100]}..."
            add_alert(query_info)

            if @config.auto_kill_rogue_processes && duration_minutes >= @config.query_kill_threshold_minutes
              terminate_result = execute_query("SELECT pg_terminate_backend(#{row['pid']});")
              if terminate_result && terminate_result.first['pg_terminate_backend'] == 't'
                add_alert("    ---> SUCESSO: Consulta PID #{row['pid']} TERMINADA. <---")
              else
                add_alert("    ---> ERRO: Falha ao TERMINAR a consulta PID #{row['pid']}. <---")
              end
            end
          end
        end
      end

      def monitor_cache_hit_ratio
        result_cache = execute_query(%Q{
          SELECT
            sum(heap_blks_read) AS heap_read, sum(heap_blks_hit) AS heap_hit,
            (CASE WHEN (sum(heap_blks_hit) + sum(heap_blks_read)) > 0 THEN (sum(heap_blks_hit) * 100.0) / (sum(heap_blks_hit) + sum(heap_blks_read)) ELSE 0 END) AS heap_hit_ratio,
            sum(idx_blks_read) AS idx_read, sum(idx_blks_hit) AS idx_hit,
            (CASE WHEN (sum(idx_blks_hit) + sum(idx_blks_read)) > 0 THEN (sum(idx_blks_hit) * 100.0) / (sum(idx_blks_hit) + sum(idx_blks_read)) ELSE 0 END) AS idx_hit_ratio
          FROM pg_statio_all_tables
          WHERE schemaname = 'public';
        })

        if result_cache && result_cache.any?
          row = result_cache.first
          if row['heap_hit_ratio'] && row['idx_hit_ratio']
            if row['heap_hit_ratio'].to_f < @config.heap_cache_hit_ratio_min
              add_alert("AVISO: Heap Cache Hit Ratio baixo (#{row['heap_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas.")
            end
            if row['idx_hit_ratio'].to_f < @config.index_cache_hit_ratio_min
              add_alert("AVISO: Index Cache Hit Ratio baixo (#{row['idx_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas.")
            end
          end
        end
      end
    end
  end
end
