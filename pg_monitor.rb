require 'pg'
require 'json'
require 'time'
require 'mail'
require 'fileutils'
require 'yaml'

# --- 1. PgMonitorConfig: Handles loading configuration ---
class PgMonitorConfig
  attr_reader :db_host, :db_port, :db_name, :db_user, :db_password
  attr_reader :sender_email, :sender_password, :receiver_email, :smtp_address, :smtp_port, :smtp_domain
  attr_reader :iostat_threshold_kb_s, :iostat_device, :cpu_alert_threshold,
              :query_alert_threshold_minutes, :query_kill_threshold_minutes,
              :heap_cache_hit_ratio_min, :index_cache_hit_ratio_min, :table_growth_threshold_percent
  attr_reader :alert_cooldown_minutes, :last_alert_file, :last_deadlock_file # Added last_deadlock_file
  attr_reader :log_file, :log_level
  attr_reader :pg_log_path, :pg_log_file_pattern
  attr_reader :auto_kill_rogue_processes
  attr_reader :disk_space_threshold_percent # New config
  attr_reader :replication_lag_bytes_threshold, :replication_lag_time_threshold_seconds # New config

  def initialize
    config_file = File.expand_path('../config/pg_monitor_config.yml', __FILE__)
    unless File.exist?(config_file)
      raise "Configuration file not found: #{config_file}. Please ensure it exists in the 'config/' directory."
    end
    config = YAML.load_file(config_file)

    # Database configurations
    @db_host = config['database']['host']
    @db_port = config['database']['port']
    @db_name = config['database']['name']
    @db_user = ENV['PG_USER']
    @db_password = ENV['PG_PASSWORD']
    unless @db_user && @db_password
      raise "Environment variables PG_USER and PG_PASSWORD must be set."
    end

    # Email configurations
    @sender_email = config['email']['sender_email']
    @sender_password = ENV['EMAIL_PASSWORD']
    @receiver_email = config['email']['receiver_email']
    @smtp_address = config['email']['smtp_address']
    @smtp_port = config['email']['smtp_port']
    @smtp_domain = config['email']['smtp_domain']
    unless @sender_password
      raise "Environment variable EMAIL_PASSWORD must be set."
    end

    # Alert thresholds
    @iostat_threshold_kb_s = config['thresholds']['iostat_threshold_kb_s']
    @iostat_device = config['thresholds']['iostat_device']
    @cpu_alert_threshold = config['thresholds']['cpu_threshold_percent']
    @query_alert_threshold_minutes = config['thresholds']['query_alert_threshold_minutes']
    @query_kill_threshold_minutes = config['thresholds']['query_kill_threshold_minutes']
    @heap_cache_hit_ratio_min = config['thresholds']['heap_cache_hit_ratio_min']
    @index_cache_hit_ratio_min = config['thresholds']['index_cache_hit_ratio_min']
    @table_growth_threshold_percent = config['thresholds']['table_growth_threshold_percent']
    
    # New thresholds
    @disk_space_threshold_percent = config['thresholds']['disk_space_threshold_percent']
    @replication_lag_bytes_threshold = config['thresholds']['replication_lag_bytes_threshold']
    @replication_lag_time_threshold_seconds = config['thresholds']['replication_lag_time_threshold_seconds']


    # Cooldown settings
    @alert_cooldown_minutes = config['cooldown']['alert_cooldown_minutes']
    @last_alert_file = config['cooldown']['last_alert_file']
    @last_deadlock_file = config['cooldown']['last_deadlock_file'] # New config
    FileUtils.mkdir_p(File.dirname(@last_alert_file)) # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(@last_deadlock_file)) # Ensure directory exists


    # Logging settings
    @log_file = config['logging']['log_file']
    @log_level = config['logging']['log_level']
    FileUtils.mkdir_p(File.dirname(@log_file)) # Ensure directory exists

    # PostgreSQL logs path
    @pg_log_path = config['postgresql_logs']['path']
    @pg_log_file_pattern = config['postgresql_logs']['file_pattern']

    # Feature toggles
    @auto_kill_rogue_processes = config['features']['auto_kill_rogue_processes']
  end
end

# --- 2. PgConnection: Handles database connection and queries ---
class PgConnection
  def initialize(config)
    @config = config
    @conn = nil
  end

  def connect
    @conn = PG.connect(
      host: @config.db_host,
      port: @config.db_port,
      dbname: @config.db_name,
      user: @config.db_user,
      password: @config.db_password
    )
    @conn
  rescue PG::Error => e
    message = "Erro ao conectar ao banco de dados: #{e.message}"
    raise 
  end

  def execute_query(query)
    @conn.exec(query)
  rescue PG::Error => e
    puts "Erro ao executar consulta: #{e.message}. Query: #{query.strip[0..100]}..."
    nil
  end

  def close
    @conn.close if @conn && !@conn.finished?
  end

  # Allow direct access to the connection object for specific cases like pg_amcheck
  def raw_connection
    @conn
  end
end

# --- 3. EmailSender: Manages sending emails with cooldown ---
class EmailSender
  def initialize(config)
    @config = config
    Mail.defaults do
      delivery_method :smtp, {
        address: @config.smtp_address,
        port: @config.smtp_port,
        domain: @config.smtp_domain,
        user_name: @config.sender_email,
        password: @config.sender_password,
        authentication: 'plain',
        enable_starttls_auto: true
      }
    end
  end

  def send_alert_email(subject, body, alert_type = "generic_alert")
    FileUtils.mkdir_p(File.dirname(@config.last_alert_file)) unless File.directory?(File.dirname(@config.last_alert_file))

    last_alert_times = File.exist?(@config.last_alert_file) ? JSON.parse(File.read(@config.last_alert_file)) : {}
    last_sent_time_str = last_alert_times[alert_type]
    last_sent_time = last_sent_time_str ? Time.parse(last_sent_time_str) : nil

    current_local_time = Time.now.strftime('%d/%m/%Y %H:%M:%S')

    if last_sent_time && (Time.now - last_sent_time) < @config.alert_cooldown_minutes * 60
      puts "[#{current_local_time}] Alerta do tipo '#{alert_type}' suprimido devido ao cooldown de #{@config.alert_cooldown_minutes} minutos. Último envio: #{last_sent_time_str}."
      return
    end

    puts "[#{current_local_time}] Enviando e-mail para #{@config.receiver_email} com o assunto: #{subject}"
    Mail.deliver do
      to @config.receiver_email
      from @config.sender_email
      subject subject
      body body
    end
    puts "[#{current_local_time}] E-mail enviado com sucesso."

    last_alert_times[alert_type] = Time.now.iso8601
    File.write(@config.last_alert_file, JSON.pretty_generate(last_alert_times))

  rescue StandardError => e
    puts "[#{current_local_time}] Erro ao enviar e-mail: #{e.message}"
    puts "[#{current_local_time}] Verifique as configurações de SMTP e a senha do aplicativo (se estiver usando Gmail)."
  end
end

# --- Base MetricCollector ---
class MetricCollector
  def initialize(pg_connection, config, alert_messages)
    @pg_conn = pg_connection
    @config = config
    @alert_messages = alert_messages # Array to store messages
  end
end

# --- 4. CriticalMetrics: High-frequency monitoring ---
class CriticalMetrics < MetricCollector
  def monitor
    puts "\n--- Monitoramento de Alta Frequência (Crítico) ---"

    monitor_cpu
    monitor_active_connections
    monitor_long_transactions
    monitor_active_locks
    monitor_xid_wraparound
    monitor_io
    monitor_long_running_queries
    monitor_cache_hit_ratio
    monitor_table_activity
    monitor_temp_files_usage
    monitor_checkpoint_activity
    monitor_replication_lag 
    monitor_deadlocks 
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
              @alert_messages << "ALERTA: Alto uso de CPU detectado! Uso total: #{'%.2f' % used_cpu_percent}% (Limiar: #{@config.cpu_alert_threshold}%)."
              @alert_messages << "  Consultas ativas que podem estar contribuindo para o pico de CPU:"

              active_queries_for_cpu = @pg_conn.execute_query(%Q{
                SELECT
                  pid, usename, application_name, query,
                  age(now(), query_start) AS query_duration,
                  state
                FROM pg_stat_activity
                WHERE state = 'active' AND backend_type = 'client backend'
                ORDER BY query_duration DESC
                LIMIT 5;
              })
              if active_queries_for_cpu && active_queries_for_cpu.any?
                active_queries_for_cpu.each do |row|
                  @alert_messages << "    - PID: #{row['pid']}, Usuário: #{row['usename']}, Estado: #{row['state']}, Duração: #{row['query_duration']}, Query: #{row['query'].strip[0..100]}..."
                end
              else
                @alert_messages << "    Nenhuma consulta ativa significativa encontrada no PostgreSQL durante este período de alto CPU."
              end
            end
          else
            puts "AVISO: Não foi possível parsear a saída do mpstat (%idle). Verifique o formato ou a versão do mpstat."
          end
        else
          puts "AVISO: Linha 'Average: all' não encontrada na saída do mpstat. Verifique o formato do comando ou a saída."
        end
      else
        puts "AVISO: mpstat não retornou dados. Certifique-se de que está instalado e acessível no PATH."
      end
    rescue Errno::ENOENT
      puts "ERRO: Comando 'mpstat' não encontrado. Certifique-se de que o pacote 'sysstat' está instalado."
    rescue StandardError => e
      puts "Erro ao executar mpstat ou processar saída: #{e.message}"
    end
  end

  def monitor_active_connections
    result_conn = @pg_conn.execute_query("SELECT count(*) AS total_connections FROM pg_stat_activity;")
    if result_conn
      total_connections = result_conn.first['total_connections'].to_i
      result_max = @pg_conn.execute_query("SHOW max_connections;")
      if result_max
        max_connections = result_max.first['max_connections'].to_i
        if total_connections >= max_connections * 0.9
          @alert_messages << "ALERTA CRÍTICO: Conexões (#{total_connections}) estão muito próximas do limite máximo (#{max_connections})!"
        end
      end
    end
  end

  def monitor_long_transactions
    result_long_tx = @pg_conn.execute_query(%Q{
      SELECT
        pid, usename, application_name, query,
        age(now(), query_start) AS query_duration
      FROM pg_stat_activity
      WHERE state IN ('active', 'idle in transaction') AND age(now(), query_start) > INTERVAL '3 minutes'
      ORDER BY query_duration DESC;
    })

    if result_long_tx && result_long_tx.any?
      @alert_messages << "ALERTA CRÍTICO: Transações Muito Longas/Inativas Detectadas (>= 3 min):"
      result_long_tx.each do |row|
        @alert_messages << "  PID: #{row['pid']}, Usuário: #{row['usename']}, Duração: #{row['query_duration']}, Query: #{row['query'].strip[0..100]}..."
      end
    end
  end

  def monitor_active_locks
    puts "\n--- Verificando Bloqueios Ativos Persistentes ---"
    result_locks = @pg_conn.execute_query(%Q{
      SELECT
          blocking_activity.pid AS blocking_pid,
          blocking_activity.usename AS blocking_user,
          blocking_activity.application_name AS blocking_app,
          blocking_activity.query AS blocking_query,
          blocked_activity.pid AS blocked_pid,
          blocked_activity.usename AS blocked_user,
          blocked_activity.application_name AS blocked_app,
          blocked_activity.query AS blocked_query,
          blocked_activity.wait_event_type,
          blocked_activity.wait_event,
          blocking_locks.locktype AS lock_type,
          blocking_locks.mode AS lock_mode,
          pg_class.relname AS locked_table_name,
          age(now(), blocked_activity.query_start) AS blocked_duration
      FROM pg_catalog.pg_locks blocked_locks
      JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
      JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid AND blocking_locks.pid != blocked_locks.pid
      JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
      LEFT JOIN pg_class ON pg_class.oid = blocked_locks.relation
      WHERE NOT blocked_locks.granted AND age(now(), blocked_activity.query_start) > INTERVAL '30 seconds';
    })

    if result_locks && result_locks.any?
      @alert_messages << "ALERTA CRÍTICO: Bloqueios Ativos Persistentes Detectados (>= 30s):"
      result_locks.each do |row|
        @alert_messages << "  Bloqueado (PID: #{row['blocked_pid']}, User: #{row['blocked_user']}): #{row['blocked_query'].to_s.strip[0..100]}... (Duração: #{row['blocked_duration']})"
        @alert_messages << "  Bloqueador (PID: #{row['blocking_pid']}, User: #{row['blocking_user']}): #{row['blocking_query'].to_s.strip[0..100]}..."
        @alert_messages << "  Tipo de Bloqueio: #{row['lock_type']}, Modo: #{row['lock_mode']}"
        @alert_messages << "  Tabela Envolvida: #{row['locked_table_name'] || 'N/A'}"
        @alert_messages << "  Tipo de Espera: #{row['wait_event_type']}, Evento: #{row['wait_event']}"
        @alert_messages << "  ---"
      end
    end
  end

  def monitor_xid_wraparound
    result_xid = @pg_conn.execute_query(%Q{
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
          @alert_messages << "ALERTA CRÍTICO: ID de transação para '#{row['datname']}' está MUITO PRÓXIMO do limite de wraparound! Idade atual: #{xid_age} (Limite: #{freeze_max_age})."
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
            @alert_messages << "ALERTA: Alto I/O de disco em '#{@config.iostat_device}' detectado! Total: #{'%.2f' % (total_kb_s / 1024)} MB/s (Leitura: #{'%.2f' % (rkbs / 1024)} MB/s, Escrita: #{'%.2f' % (wkbs / 1024)} MB/s)."
            @alert_messages << "  Consultas ativas durante o pico de I/O:"

            active_queries_for_io = @pg_conn.execute_query(%Q{
              SELECT
                pid, usename, application_name, query,
                age(now(), query_start) AS query_duration,
                state
              FROM pg_stat_activity
              WHERE state = 'active' AND backend_type = 'client backend'
              ORDER BY query_start ASC
              LIMIT 5;
            })
            if active_queries_for_io && active_queries_for_io.any?
              active_queries_for_io.each do |row|
                @alert_messages << "    - PID: #{row['pid']}, Usuário: #{row['usename']}, Estado: #{row['state']}, Duração: #{row['query_duration']}, Query: #{row['query'].to_s.strip[0..100]}..."
              end
            else
              @alert_messages << "    Nenhuma consulta ativa significativa encontrada no PostgreSQL durante este período de alto I/O."
            end
          end
        else
          puts "AVISO: Dispositivo '#{@config.iostat_device}' não encontrado na saída do iostat. Verifique o nome do dispositivo ou se o iostat está funcionando."
        end
      else
        puts "AVISO: iostat não retornou dados. Certifique-se de que está instalado e acessível no PATH."
      end
    rescue Errno::ENOENT
      puts "ERRO: Comando 'iostat' não encontrado. Certifique-se de que o pacote 'sysstat' está instalado."
    rescue StandardError => e
      puts "Erro ao executar iostat ou processar saída: #{e.message}"
    end
  end

  def monitor_long_running_queries
    puts "\n--- Verificando e Matando Consultas Excessivamente Longas ---"
    long_running_queries = @pg_conn.execute_query(%Q{
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
      @alert_messages << "ALERTA CRÍTICO: Consultas rodando há mais de #{@config.query_alert_threshold_minutes} minutos (e potencialmente encerradas):"
      long_running_queries.each do |row|
        duration_minutes = row['duration_seconds'].to_i / 60
        query_info = "  PID: #{row['pid']}, Usuário: #{row['usename']}, App: #{row['application_name']}, Cliente: #{row['client_addr']}, Duração: #{duration_minutes} min, Query: #{row['query'].to_s.strip[0..100]}..."
        @alert_messages << query_info

        if @config.auto_kill_rogue_processes && duration_minutes >= @config.query_kill_threshold_minutes
          puts "Tentando TERMINAR a consulta PID #{row['pid']} (duração: #{duration_minutes} min)..."
          terminate_result = @pg_conn.execute_query("SELECT pg_terminate_backend(#{row['pid']});")
          if terminate_result && terminate_result.first['pg_terminate_backend'] == 't'
            @alert_messages << "    ---> SUCESSO: Consulta PID #{row['pid']} TERMINADA. <---"
            puts "Consulta PID #{row['pid']} terminada com sucesso."
          else
            @alert_messages << "    ---> ERRO: Falha ao TERMINAR a consulta PID #{row['pid']}. <---"
            puts "Falha ao terminar a consulta PID #{row['pid']}."
          end
        else
          puts "Consulta PID #{row['pid']} (duração: #{duration_minutes} min) será apenas alertada, ainda não será encerrada."
        end
      end
    else
      puts "Nenhuma consulta excessivamente longa encontrada."
    end
  end

  def monitor_cache_hit_ratio
    puts "\n--- Verificando Cache Hit Ratio ---"
    result_cache = @pg_conn.execute_query(%Q{
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
          @alert_messages << "AVISO: Heap Cache Hit Ratio baixo (#{row['heap_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas."
        end
        if row['idx_hit_ratio'].to_f < @config.index_cache_hit_ratio_min
          @alert_messages << "AVISO: Index Cache Hit Ratio baixo (#{row['idx_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas."
        end
      end
    end
  end

  def monitor_table_activity
    puts "\n--- Verificando Atividade Recente de Tabelas (Top 5 por Tamanho) ---"
    result_table_activity = @pg_conn.execute_query(%Q{
        SELECT
            relname AS table_name,
            schemaname AS schema_name,
            pg_size_pretty(pg_relation_size(relid)) AS current_size,
            n_tup_ins,
            n_tup_upd,
            n_tup_del,
            n_live_tup,
            n_dead_tup,
            last_analyze,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'manutencao')
        ORDER BY pg_relation_size(relid) DESC
        LIMIT 5;
    })

    if result_table_activity && result_table_activity.any?
        @alert_messages << "INFO: Top 5 Tabelas por Tamanho com Atividade Recente (Desde último ANALYZE/VACUUM):"
        result_table_activity.each do |row|
            @alert_messages << "  - Tabela: #{row['schema_name']}.#{row['table_name']}, Tamanho: #{row['current_size']}"
            @alert_messages << "    Inserções: #{row['n_tup_ins']}, Atualizações: #{row['n_tup_upd']}, Deleções: #{row['n_tup_del']}"
            @alert_messages << "    Tuplas Vivas: #{row['n_live_tup']}, Tuplas Mortas: #{row['n_dead_tup']}"
            @alert_messages << "    Último Analyze: #{row['last_analyze'] || 'Nunca'}, Último Autovacuum: #{row['last_autovacuum'] || 'Nunca'}"
        end
    else
        puts "Nenhuma tabela de usuário encontrada para análise de atividade."
    end
  end

  def monitor_temp_files_usage
    puts "\n--- Verificando Consultas com Uso Elevado de Temporary Files (Requer pg_stat_statements) ---"
    result_temp_files = @pg_conn.execute_query(%Q{
        SELECT
            query,
            temp_blks_read,
            temp_blks_written,
            calls,
            total_exec_time,
            mean_exec_time
        FROM pg_stat_statements
        WHERE temp_blks_written > 0
        ORDER BY temp_blks_written DESC
        LIMIT 5;
    })

    if result_temp_files && result_temp_files.any?
        @alert_messages << "ALERTA: Top 5 Consultas Usando Temporary Files (indicam necessidade de mais memória ou otimização):"
        result_temp_files.each do |row|
            @alert_messages << "  - Query: #{row['query'].to_s.strip[0..100]}..."
            @alert_messages << "    Blocos Lidos Temp: #{row['temp_blks_read']}, Blocos Escritos Temp: #{row['temp_blks_written']}"
            @alert_messages << "    Chamadas: #{row['calls']}, Tempo Total: #{'%.2f' % row['total_exec_time']}ms, Tempo Médio: #{'%.2f' % row['mean_exec_time']}ms"
        end
    else
        puts "Nenhuma consulta usando temporary files em grande volume detectada."
    end
  end

  def monitor_checkpoint_activity
    puts "\n--- Verificando Atividade de Checkpoint (I/O de Escrita) ---"
    result_bgwriter = @pg_conn.execute_query(%Q{
        SELECT
            checkpoints_timed,
            checkpoints_req,
            checkpoint_write_time,
            checkpoint_sync_time,
            buffers_checkpoint,
            buffers_clean,
            maxwritten_clean,
            buffers_backend,
            buffers_backend_fsync,
            buffers_alloc
        FROM pg_stat_bgwriter;
    })

    if result_bgwriter && result_bgwriter.any?
        row = result_bgwriter.first
        if row['maxwritten_clean'].to_i > 0
            @alert_messages << "ALERTA: O Background Writer atingiu o limite de buffers sujos (maxwritten_clean > 0). Isso indica I/O de escrita intenso. Considere ajustar wal_buffers, max_wal_size, checkpoint_timeout."
            @alert_messages << "  - Checkpoints Agendados: #{row['checkpoints_timed']}, Checkpoints Solicitados: #{row['checkpoints_req']}"
            @alert_messages << "  - Tempo de Escrita Checkpoint: #{row['checkpoint_write_time']}ms, Tempo de Sync Checkpoint: #{row['checkpoint_sync_time']}ms"
            @alert_messages << "  - Buffers Escritos por Checkpoint: #{row['buffers_checkpoint']}, Buffers Escritos por Backend: #{row['buffers_backend']}"
        else
          puts "Atividade de checkpoint normal (maxwritten_clean é 0)."
        end
    else
        puts "Não foi possível coletar métricas de pg_stat_bgwriter."
    end
  end

  # --- NEW: Replication Lag Monitoring ---
  def monitor_replication_lag
    puts "\n--- Verificando Lag de Replicação ---"
    # This query assumes you are running on the primary and checking its standbys
    # or you are running on a standby and checking its lag behind primary.
    # For simplicity, this checks for active standbys connected to *this* instance.
    result_replication = @pg_conn.execute_query(%Q{
      SELECT
          pid,
          usesysid,
          usename,
          application_name,
          client_addr,
          client_hostname,
          client_port,
          backend_start,
          backend_xmin,
          state,
          sent_lsn,
          write_lsn,
          flush_lsn,
          replay_lsn,
          sync_priority,
          sync_state,
          pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes,
          EXTRACT(EPOCH FROM (NOW() - backend_start)) AS backend_age_seconds
      FROM pg_stat_replication;
    })

    if result_replication && result_replication.any?
      result_replication.each do |row|
        lag_bytes = row['lag_bytes'].to_i

        # Check for state indicating lag or significant byte lag
        if row['state'] == 'lagging'
            @alert_messages << "ALERTA CRÍTICO: Standby '#{row['application_name']}' (Client: #{row['client_addr']}) está em estado 'lagging'! Lag em bytes: #{pg_size_pretty(lag_bytes)}."
        elsif lag_bytes > @config.replication_lag_bytes_threshold
          @alert_messages << "ALERTA: Standby '#{row['application_name']}' (Client: #{row['client_addr']}) com lag de bytes significativo: #{pg_size_pretty(lag_bytes)} (Limiar: #{pg_size_pretty(@config.replication_lag_bytes_threshold)})."
        elsif row['backend_age_seconds'].to_f > @config.replication_lag_time_threshold_seconds
          @alert_messages << "AVISO: Standby '#{row['application_name']}' (Client: #{row['client_addr']}) conectado há muito tempo sem atualização (possível lag de tempo): #{'%.0f' % row['backend_age_seconds'].to_f} segundos (Limiar: #{@config.replication_lag_time_threshold_seconds}s)."
        else
          puts "Replicação para '#{row['application_name']}' está ok. Lag: #{pg_size_pretty(lag_bytes)}."
        end
      end
    else
      puts "Nenhuma réplica ativa encontrada (ou esta é uma instância standby sem réplicas)."
    end
  rescue PG::UndefinedFunction => e
    @alert_messages << "ERRO: Função pg_wal_lsn_diff ou pg_current_wal_lsn não encontrada. Verifique sua versão do PostgreSQL (requer 9.4+)."
  rescue StandardError => e
    puts "Erro ao verificar lag de replicação: #{e.message}"
    @alert_messages << "ERRO: Falha ao verificar lag de replicação: #{e.message}"
  end

  # Helper for pg_size_pretty equivalent
  def pg_size_pretty(bytes)
    return '0 B' if bytes == 0
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    i = (Math.log(bytes) / Math.log(1024)).floor
    "#{'%.2f' % (bytes / (1024 ** i))} #{units[i]}"
  end

  # --- NEW: Deadlock Detection ---
  def monitor_deadlocks
    puts "\n--- Verificando Deadlocks Recentes ---"
    current_deadlock_count = @pg_conn.execute_query("SELECT deadlocks FROM pg_stat_database WHERE datname = current_database();")

    if current_deadlock_count && current_deadlock_count.any?
      new_deadlock_count = current_deadlock_count.first['deadlocks'].to_i

      # Load last known count
      last_deadlock_data = File.exist?(@config.last_deadlock_file) ? JSON.parse(File.read(@config.last_deadlock_file)) : {}
      last_known_count = last_deadlock_data['deadlock_count'].to_i

      if new_deadlock_count > last_known_count
        newly_detected_deadlocks = new_deadlock_count - last_known_count
        @alert_messages << "ALERTA: #{newly_detected_deadlocks} novo(s) deadlock(s) detectado(s) desde o último check! Total de deadlocks: #{new_deadlock_count}. Verifique os logs do PostgreSQL para mais detalhes."

        # Optionally, try to pull relevant log entries if log path is configured
        if @config.pg_log_path && File.directory?(@config.pg_log_path)
          log_files = Dir.glob(File.join(@config.pg_log_path, @config.pg_log_file_pattern)).sort_by { |f| File.mtime(f) }.last(2) # Check last 2 log files
          deadlock_log_entries = []
          log_files.each do |log_file|
            File.foreach(log_file) do |line|
              if line.include?('deadlock detected') && Time.parse(line.split[0..1].join(' ')) > Time.now - 3600 # Check in last hour
                deadlock_log_entries << line.strip
              end
            end
          end
          if deadlock_log_entries.any?
            @alert_messages << "  Últimos Deadlocks nos logs:"
            deadlock_log_entries.each { |entry| @alert_messages << "    - #{entry}" }
          else
            @alert_messages << "  (Nenhum detalhe de deadlock recente encontrado nos logs configurados)."
          end
        end
      else
        puts "Nenhum novo deadlock detectado. Contagem atual: #{new_deadlock_count}."
      end

      # Save current count for next run
      File.write(@config.last_deadlock_file, JSON.pretty_generate({'deadlock_count' => new_deadlock_count}))
    else
      puts "Não foi possível obter a contagem de deadlocks de pg_stat_database."
      @alert_messages << "ERRO: Falha ao obter a contagem de deadlocks de pg_stat_database."
    end
  rescue StandardError => e
    puts "Erro ao verificar deadlocks: #{e.message}"
    @alert_messages << "ERRO: Falha ao verificar deadlocks: #{e.message}"
  end
end

# --- 5. PerformanceMetrics: Medium-frequency monitoring ---
class PerformanceMetrics < MetricCollector
  def monitor
    puts "\n--- Monitoramento de Média Frequência (Desempenho) ---"
    monitor_autovacuum
  end

  private

  def monitor_autovacuum
    result_autovac = @pg_conn.execute_query(%Q{
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
      @alert_messages << "AVISO: Tabelas com autovacuum inativo ou muito antigo (últimos 5 com tuplas mortas):"
      result_autovac.each do |row|
        @alert_messages << "  Tabela: #{row['relname']}, Último AV: #{row['last_autovacuum'] || 'Nunca'}, Última AA: #{row['last_autoanalyze'] || 'Nunca'}, Tuplas Mortas: #{row['n_dead_tup']}"
      end
    end
  end
end

# --- 6. OptimizationMetrics: Low-frequency monitoring ---
class OptimizationMetrics < MetricCollector
  def monitor
    puts "\n--- Monitoramento de Baixa Frequência (Otimização/Tendências) ---"
    monitor_disk_space # Old, but now also calls new disk_space_partition
    monitor_disk_space_partition # New: Disk Space Partition
    monitor_repeated_and_unused_indexes
    monitor_slow_queries
    analyze_bloat # New: Detailed Bloat Analysis
  end

  private

  def monitor_disk_space
    result_disk = @pg_conn.execute_query("SELECT pg_size_pretty(pg_database_size('#{@config.db_name}')) AS db_size;")
    if result_disk
      db_size = result_disk.first['db_size']
      puts "Tamanho do banco de dados '#{@config.db_name}': #{db_size}"
      @alert_messages << "INFO: Tamanho total do banco de dados '#{@config.db_name}': #{db_size}."
    end
  end

  # --- NEW: Disk Space Monitoring (Partition) ---
  def monitor_disk_space_partition
    puts "\n--- Verificando Espaço em Disco da Partição de Dados do PostgreSQL ---"
    data_directory_result = @pg_conn.execute_query("SHOW data_directory;")
    if data_directory_result && data_directory_result.any?
      data_directory = data_directory_result.first['data_directory']
      
      begin
        df_output = `df -h #{data_directory} 2>/dev/null`
        lines = df_output.split("\n")
        
        # Look for the line that starts with /dev/ or a mounted filesystem path
        disk_info_line = lines.find { |line| line.start_with?('/') || line.start_with?('Filesystem') }

        if disk_info_line && !disk_info_line.include?('Filesystem') # Exclude header line if found
          parts = disk_info_line.split(/\s+/)
          
          # Find the column containing percentage used (usually 5th or 6th, looking for '%' at the end)
          use_percent_str = parts.find { |p| p.end_with?('%') }
          
          if use_percent_str
            used_percent = use_percent_str.chomp('%').to_i
            mounted_on = parts.last # The last part is usually the mount point

            if used_percent >= @config.disk_space_threshold_percent
              @alert_messages << "ALERTA CRÍTICO: A partição de dados do PostgreSQL (#{mounted_on}) está com #{used_percent}% de uso, próximo do limite! (Limiar: #{@config.disk_space_threshold_percent}%)"
              @alert_messages << "  Caminho do diretório de dados: #{data_directory}"
            else
              puts "Espaço em disco na partição de dados (#{mounted_on}) está ok: #{used_percent}% de uso."
            end
          else
            puts "AVISO: Não foi possível parsear a porcentagem de uso na saída do 'df' para '#{data_directory}'."
          end
        else
          puts "AVISO: Informações de disco para '#{data_directory}' não encontradas na saída do 'df'."
        end
      rescue Errno::ENOENT
        @alert_messages << "ERRO: Comando 'df' não encontrado. Verifique se está disponível no PATH do sistema."
      rescue StandardError => e
        @alert_messages << "ERRO: Falha ao verificar espaço em disco da partição de dados: #{e.message}"
      end
    else
      puts "Não foi possível obter o diretório de dados do PostgreSQL."
      @alert_messages << "ERRO: Falha ao obter o diretório de dados do PostgreSQL para verificar espaço em disco."
    end
  end

  def monitor_repeated_and_unused_indexes
    result_repeated_idx = @pg_conn.execute_query(%Q{
      SELECT
          pg_size_pretty(SUM(pg_relation_size(idx))) AS size,
          (array_agg(idx))[1] AS idx1,
          (array_agg(idx))[2] AS idx2,
          tbl
      FROM (
          SELECT
              indexrelid AS idx,
              c.relname AS tbl,
              (indkey::text) AS key_cols,
              (indoption::text) AS key_options,
              indpred IS NOT NULL AS has_predicate
          FROM pg_index i
          JOIN pg_class c ON i.indexrelid = c.oid
          JOIN pg_class t ON i.indrelid = t.oid
          WHERE NOT indisprimary AND NOT indisexclusion AND NOT indislive
      ) sub
      GROUP BY tbl, key_cols, key_options, has_predicate
      HAVING COUNT(*) > 1
      ORDER BY SUM(pg_relation_size(idx)) DESC
      LIMIT 3;
    })

    if result_repeated_idx && result_repeated_idx.any?
      @alert_messages << "INFORMAÇÃO: Índices Repetidos/Redundantes Encontrados (Top 3 por tamanho):"
      result_repeated_idx.each do |row|
        @alert_messages << "  Tabela: #{row['tbl']}, Tamanho Total: #{row['size']}, Índices: #{[row['idx1'], row['idx2']].compact.join(', ')}. Considere remover."
      end
    end

    result_unused_idx = @pg_conn.execute_query(%Q{
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
      @alert_messages << "INFORMAÇÃO: Índices Não Utilizados Encontrados (Top 10 por tamanho, >1GB):"
      result_unused_idx.each do |row|
        @alert_messages << "  Tabela: #{row['table_name']}, Índice: #{row['index_name']}, Tamanho: #{row['index_size']}. Considere remover."
      end
    end
  end

  def monitor_slow_queries
    result_slow_queries = @pg_conn.execute_query(%Q{
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
      @alert_messages << "INFORMAÇÃO: Top 10 Consultas Mais Lentas (total_time):"
      result_slow_queries.each do |row|
        @alert_messages << "  Query: #{row['query'].to_s.strip[0..100]}..., Chamadas: #{row['calls']}, Tempo Total: #{'%.2f' % row['total_time']}ms, Tempo Médio: #{'%.2f' % row['mean_time']}ms, Linhas: #{row['rows']}"
      end
    end
  end

  # --- NEW: Detailed Bloat Analysis ---
  def analyze_bloat
    puts "\n--- Análise Detalhada de Bloat (Inchaço) em Tabelas e Índices ---"
    # This query provides an estimate of bloat. It's a common query used for this purpose.
    # It might be resource-intensive on very large databases.
    # Consider using pg_repack for online bloat reduction.
    result_bloat = @pg_conn.execute_query(%Q{
      WITH pg_class_statistics AS (
        SELECT
            c.oid,
            c.relname,
            c.relkind,
            c.relpages,
            c.reltuples,
            pg_relation_size(c.oid) AS total_bytes,
            COALESCE(TO_CHAR(c.reloptions, '9999'), '') AS reloptions_str, -- convert array to string for easy searching
            CASE c.relkind
                WHEN 'r' THEN 'table'
                WHEN 'i' THEN 'index'
                WHEN 't' THEN 'toast'
                ELSE c.relkind::text
            END AS object_type,
            ns.nspname AS schema_name
        FROM pg_class c
        JOIN pg_namespace ns ON ns.oid = c.relnamespace
        WHERE c.relkind IN ('r','i','t')
          AND ns.nspname NOT IN ('pg_catalog','information_schema')
          AND NOT EXISTS (SELECT 1 FROM pg_depend WHERE objid = c.oid AND deptype = 'e') -- exclude extensions' objects
      ), bloat_data AS (
        SELECT
            ps.oid,
            ps.relname,
            ps.object_type,
            ps.schema_name,
            ps.total_bytes,
            ps.relpages,
            ps.reltuples,
            ps.reloptions_str,
            CASE ps.object_type
                WHEN 'table' THEN (
                    SELECT pg_catalog.pg_relation_size(c.oid) - (
                        SELECT COALESCE(sum(pg_catalog.pg_relation_size(i.indexrelid)), 0)
                        FROM pg_catalog.pg_index i
                        WHERE i.indrelid = c.oid AND i.indisvalid
                    ) FROM pg_class c WHERE c.oid = ps.oid
                )
                WHEN 'index' THEN ps.total_bytes
                WHEN 'toast' THEN ps.total_bytes
                ELSE 0
            END AS data_bytes
        FROM pg_class_statistics ps
      )
      SELECT
          schema_name,
          relname AS object_name,
          object_type,
          pg_size_pretty(total_bytes) AS total_size,
          pg_size_pretty(data_bytes) AS data_size,
          CASE object_type
              WHEN 'table' THEN
                  (data_bytes - (reltuples * (
                      (SELECT (SELECT setting FROM pg_settings WHERE name = 'block_size')::numeric) + COALESCE(c.reltuples_per_page, 0)
                  )))::bigint -- Simplified, assumes avg row size based on reltuples_per_page
              WHEN 'index' THEN
                  -- More complex calculation for index bloat, often requires specific formulas
                  -- A simpler proxy for index bloat is comparing actual size to estimated minimal size
                  (data_bytes - (reltuples * (SELECT (SELECT setting FROM pg_settings WHERE name = 'block_size')::numeric / 4)))::bigint -- A very rough estimate
              ELSE 0
          END AS estimated_bloat_bytes,
          (CASE WHEN total_bytes > 0 THEN (100.0 * (
              CASE object_type
                  WHEN 'table' THEN (data_bytes - (reltuples * (
                      (SELECT (SELECT setting FROM pg_settings WHERE name = 'block_size')::numeric) + COALESCE(c.reltuples_per_page, 0)
                  )))
                  WHEN 'index' THEN (data_bytes - (reltuples * (SELECT (SELECT setting FROM pg_settings WHERE name = 'block_size')::numeric / 4)))
                  ELSE 0
              END
          )) / total_bytes ELSE 0 END)::numeric(5,2) AS bloat_percentage
      FROM bloat_data bd
      LEFT JOIN pg_class c ON c.oid = bd.oid -- for reltuples_per_page in table bloat
      WHERE (data_bytes - (reltuples * (
                  (SELECT (SELECT setting FROM pg_settings WHERE name = 'block_size')::numeric) + COALESCE(c.reltuples_per_page, 0)
              ))) > (10 * 1024 * 1024) -- Bloat > 10MB
              AND reltuples > 1000 -- Only for tables with significant rows
              AND total_bytes > (50 * 1024 * 1024) -- Only for objects > 50MB
      ORDER BY estimated_bloat_bytes DESC
      LIMIT 10;
    })

    if result_bloat && result_bloat.any?
      @alert_messages << "INFORMAÇÃO: Top 10 Objetos com Bloat Estimado (Inchaço > 10MB, Objeto > 50MB, Tuplas > 1000):"
      result_bloat.each do |row|
        @alert_messages << "  - Objeto: #{row['schema_name']}.#{row['object_name']} (Tipo: #{row['object_type']})"
        @alert_messages << "    Tamanho Total: #{row['total_size']}, Tamanho Dados: #{row['data_size']}"
        @alert_messages << "    Bloat Estimado: #{pg_size_pretty(row['estimated_bloat_bytes'].to_i)} (#{row['bloat_percentage']}%)"
        @alert_messages << "    Ação: Considere VACUUM FULL ou pg_repack (para tabelas), REINDEX (para índices)."
      end
    else
      puts "Nenhum bloat significativo detectado (considerando limites de 10MB bloat, 50MB total, 1000 tuplas)."
    end
  rescue PG::Error => e
    # This query is complex and might fail on older PG versions or if certain stats are missing.
    puts "ERRO: Falha ao executar análise de bloat: #{e.message}. Esta query pode ser sensível à versão do PostgreSQL ou extensões. Detalhes: #{e.message}"
    @alert_messages << "ERRO: Falha na análise de bloat: #{e.message}. Verifique a compatibilidade da query com sua versão do PG."
  rescue StandardError => e
    puts "Erro inesperado na análise de bloat: #{e.message}"
    @alert_messages << "ERRO: Erro inesperado na análise de bloat: #{e.message}"
  end

  # Helper for pg_size_pretty equivalent (duplicated for now, can be a shared utility)
  def pg_size_pretty(bytes)
    return '0 B' if bytes.nil? || bytes == 0
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    i = (Math.log(bytes) / Math.log(1024)).floor
    "#{'%.2f' % (bytes / (1024 ** i))} #{units[i]}"
  end
end


# --- 7. CorruptionChecker: Data corruption tests ---
class CorruptionChecker < MetricCollector
  def check
    puts "\n--- TESTE DE CORRUPÇÃO DE DADOS (pg_amcheck) ---"

    check_block_checksums
    run_custom_sanity_checks
  end

  private

  def check_block_checksums
    begin
      result_checksums = @pg_conn.execute_query(%Q{
        SELECT (SELECT setting FROM pg_settings WHERE name = 'data_checksums') as data_checksums_enabled;
      })

      if result_checksums && result_checksums.any?
        row = result_checksums.first
        if row['data_checksums_enabled'] == 'on'
          puts "Checksums de dados estão ATIVADOS."
          puts "Executando pg_amcheck --check-relations --check-indexes..."

          pg_amcheck_conn_string = "-h #{@config.db_host} -p #{@config.db_port} -U #{@config.db_user} -d #{@config.db_name}"
          # Important: Do NOT directly pass PGPASSWORD on the command line for security.
          # Use the PGPASSWORD environment variable.
          command = "PGPASSWORD=#{@config.db_password} pg_amcheck #{pg_amcheck_conn_string} --check-relations --check-indexes --progress 2>&1"
          puts "Comando a ser executado: pg_amcheck #{pg_amcheck_conn_string.gsub(@config.db_password, '********')} --check-relations --check-indexes --progress"

          amcheck_output = `#{command}`
          amcheck_exit_status = $?.exitstatus

          puts "Saída do pg_amcheck:\n#{amcheck_output}"

          if amcheck_exit_status == 0
            @alert_messages << "INFO: pg_amcheck executado com sucesso. Nenhuma corrupção de dados ou índice detectada."
          else
            @alert_messages << "ALERTA CRÍTICO: pg_amcheck detectou PROBLEMAS de corrupção ou falhou! Saída:\n#{amcheck_output}"
            @alert_messages << "Status de saída do pg_amcheck: #{amcheck_exit_status}. Verifique os logs para detalhes."
          end

        else
          puts "Checksums de dados estão DESATIVADOS."
          @alert_messages << "AVISO: Checksums de dados estão DESATIVADOS. A detecção de corrupção com pg_amcheck é menos eficaz sem eles. Recomenda-se ativar checksums (requer reinitdb e PERDA DE DATAS)."
        end
      else
        puts "Erro ao verificar o status dos checksums no banco de dados."
        @alert_messages << "ERRO: Falha ao verificar o status dos checksums no banco de dados."
      end
    rescue PG::Error => e
      @alert_messages << "ERRO DE BANCO DE DADOS ao tentar verificar checksums: #{e.message}"
    rescue Errno::ENOENT
      @alert_messages << "ERRO: Comando 'pg_amcheck' não encontrado. Certifique-se de que o pacote 'postgresql-contrib' ou similar está instalado."
    rescue StandardError => e
      @alert_messages << "ERRO NO SCRIPT ao executar pg_amcheck: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

  def run_custom_sanity_checks
    puts "\n--- 2. Consultas de Sanidade Customizadas (ADAPTE PARA SUA ESTRUTURA!) ---"
    result_count = @pg_conn.execute_query("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
    if result_count
      count = result_count.first['count'].to_i
      puts "Contagem de tabelas públicas: #{count}"
      if count < 5
        @alert_messages << "ALERTA: Número de tabelas públicas inesperadamente baixo (#{count}). Verifique a integridade do schema."
      else
        puts "Contagem de tabelas públicas está dentro do esperado."
      end
    else
      puts "Erro ao executar consulta de contagem em information_schema.tables."
      @alert_messages << "ERRO: Falha ao executar consulta de sanidade: Contagem de tabelas públicas."
    end
    puts "\n--- Lembre-se de ADAPTAR as consultas de sanidade para seu ambiente! ---"
  end
end

# --- 8. TableSizeHistory: Saves table size historical data ---
class TableSizeHistory < MetricCollector
  def save
    puts "\n--- Salvando Histórico de Tamanho das Tabelas ---"
    begin
      @pg_conn.execute_query("CREATE SCHEMA IF NOT EXISTS manutencao;")
      @pg_conn.execute_query(%q{
        CREATE TABLE IF NOT EXISTS manutencao.size_table_history (
          data_coleta TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          schema_name TEXT,
          table_name TEXT,
          table_size_bytes BIGINT
        );
      })

      @pg_conn.execute_query(%q{
        INSERT INTO manutencao.size_table_history (data_coleta, schema_name, table_name, table_size_bytes)
        SELECT
          NOW(),
          table_schema,
          table_name,
          pg_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name))
        FROM information_schema.tables
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'manutencao')
        AND table_type = 'BASE TABLE';
      })

      puts "Tamanhos das tabelas salvos em manutencao.size_table_history com sucesso."
      @alert_messages << "INFO: Histórico de tamanho das tabelas atualizado com sucesso."
    rescue PG::Error => e
      puts "Erro ao salvar tamanhos das tabelas: #{e.message}"
      @alert_messages << "ALERTA: Falha ao salvar o histórico de tamanho das tabelas: #{e.message}"
    end
  end
end


# --- 9. PgMonitor: Main orchestrator ---
class PgMonitor
  def initialize(frequency)
    @config = PgMonitorConfig.new
    @email_sender = EmailSender.new(@config)
    @alert_messages = []
    @frequency = frequency
  end

  def run
    alert_type_for_email = "GENERIC_MONITORING_ALERT_#{@config.db_name.upcase}"

    # Connect to DB only if needed for the frequency level
    pg_connection = nil
    if ['high', 'medium', 'low', 'corruption_test', 'table_size_history'].include?(@frequency) # Added corruption_test to connect
      begin
        pg_connection = PgConnection.new(@config)
        pg_connection.connect # Establish connection here
      rescue StandardError => e
        @email_sender.send_alert_email(
          "ALERTA CRÍTICO: Falha na Conexão PostgreSQL - #{@config.db_name}",
          "Erro ao conectar ao banco de dados: #{e.message}",
          "DB_CONNECTION_ERROR_#{@config.db_name.upcase}"
        )
        puts "Erro crítico de conexão: #{e.message}"
        exit 1 # Exit if cannot connect for these levels
      end
    end

    case @frequency
    when 'high'
      puts "Executando monitoramento de ALTA frequência..."
      CriticalMetrics.new(pg_connection, @config, @alert_messages).monitor
      alert_type_for_email = "HIGH_FREQ_ALERTS_#{@config.db_name.upcase}"
    when 'medium'
      puts "Executando monitoramento de MÉDIA frequência..."
      PerformanceMetrics.new(pg_connection, @config, @alert_messages).monitor
      alert_type_for_email = "MEDIUM_FREQ_ALERTS_#{@config.db_name.upcase}"
    when 'low'
      puts "Executando monitoramento de BAIXA frequência..."
      OptimizationMetrics.new(pg_connection, @config, @alert_messages).monitor
      alert_type_for_email = "LOW_FREQ_ALERTS_#{@config.db_name.upcase}"
    when 'corruption_test'
      puts "Executando TESTE DE CORRUPÇÃO DE DADOS (pg_amcheck e Sanidade Customizada)..."
      # CorruptionChecker needs its own connection context for PGPASSWORD.
      # Re-using the existing pg_connection established above.
      CorruptionChecker.new(pg_connection, @config, @alert_messages).check
      alert_type_for_email = "CORRUPTION_TEST_ALERTS_#{@config.db_name.upcase}"
    when 'table_size_history'
      puts "Executando Salvamento do Histórico de Tamanho das Tabelas..."
      TableSizeHistory.new(pg_connection, @config, @alert_messages).save
      alert_type_for_email = "TABLE_SIZE_HISTORY_INFO_#{@config.db_name.upcase}"
    else
      puts "Nível de frequência desconhecido: #{@frequency}. Use 'high', 'medium', 'low', 'corruption_test' ou 'table_size_history'."
      exit 1
    end

    if @alert_messages.empty?
      puts "Status do PostgreSQL para '#{@frequency}' frequência: OK. Nenhum alerta detectado."
    else
      subject = "ALERTA [#{@frequency.upcase}]: Problemas/Informações no PostgreSQL - #{@config.db_name}"
      full_alert_body = "Monitoramento #{@frequency.upcase} em #{Time.now.strftime('%d/%m/%Y %H:%M:%S')} (Goiânia, GO, Brasil) detectou os seguintes problemas/informações:\n\n"
      @alert_messages.each do |msg|
        full_alert_body << "- #{msg}\n"
      end
      @email_sender.send_alert_email(subject, full_alert_body, alert_type_for_email)
    end

  rescue StandardError => e
    current_local_time = Time.now.strftime('%d/%m/%Y %H:%M:%S')
    error_message = "[#{current_local_time}] Ocorreu um erro inesperado durante o monitoramento #{@frequency}: #{e.message}\n#{e.backtrace.join("\n")}"
    @email_sender.send_alert_email(
      "ALERTA CRÍTICO: Erro no Script de Monitoramento PostgreSQL",
      error_message,
      "SCRIPT_ERROR_#{@config.db_name.upcase}"
    )
    puts error_message
  ensure
    pg_connection.close if pg_connection # Ensure the connection is closed
  end
end

# --- Script Entry Point ---
frequency_arg = ARGV[0] || 'high'
PgMonitor.new(frequency_arg).run