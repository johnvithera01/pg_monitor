require 'pg'
require 'json'
require 'time'
require 'mail' # Para envio de e-mail
require 'fileutils' # Para manipulação de diretórios/arquivos para o cooldown
require 'yaml' # Adicione esta linha para poder ler arquivos YAML

# --- Carregar Configurações do Arquivo YAML ---
CONFIG_FILE = File.expand_path('../config/pg_monitor_config.yml', __FILE__)

unless File.exist?(CONFIG_FILE)
  raise "Configuration file not found: #{CONFIG_FILE}. Please ensure it exists in the 'config/' directory."
end

CONFIG = YAML.load_file(CONFIG_FILE)

# --- Configurações do Banco de Dados (lidas do YAML e ENV) ---
DB_HOST = CONFIG['database']['host']
DB_PORT = CONFIG['database']['port']
DB_NAME = CONFIG['database']['name']
# Credenciais sensíveis: Lidas APENAS de variáveis de ambiente. Remova quaisquer fallbacks hardcoded no seu script!
DB_USER = ENV['PG_USER']
DB_PASSWORD = ENV['PG_PASSWORD']

# Verifica se as variáveis de ambiente essenciais para o DB foram definidas
unless DB_USER && DB_PASSWORD
  raise "Environment variables PG_USER and PG_PASSWORD must be set."
end

# --- Configurações de E-mail (lidas do YAML e ENV) ---
SENDER_EMAIL = CONFIG['email']['sender_email']
# Credenciais sensíveis: Lida APENAS da variável de ambiente. Remova quaisquer fallbacks hardcoded!
SENDER_PASSWORD = ENV['EMAIL_PASSWORD']
RECEIVER_EMAIL = CONFIG['email']['receiver_email']
SMTP_ADDRESS = CONFIG['email']['smtp_address']
SMTP_PORT = CONFIG['email']['smtp_port']
SMTP_DOMAIN = CONFIG['email']['smtp_domain']

# Verifica se a variável de ambiente essencial para o e-mail foi definida
unless SENDER_PASSWORD
  raise "Environment variable EMAIL_PASSWORD must be set."
end

# --- Configuração da Gem Mail (usando variáveis carregadas) ---
Mail.defaults do
  delivery_method :smtp, {
    address:   SMTP_ADDRESS,
    port:      SMTP_PORT,
    domain:    SMTP_DOMAIN,
    user_name: SENDER_EMAIL,
    password:  SENDER_PASSWORD,
    authentication: 'plain', # Ou 'login', 'cram_md5' dependendo do seu servidor SMTP
    enable_starttls_auto: true
  }
end

# --- Limiares de Alerta (lidos do YAML) ---
IOSTAT_THRESHOLD_KB_S = CONFIG['thresholds']['iostat_threshold_kb_s']
IOSTAT_DEVICE = CONFIG['thresholds']['iostat_device']
CPU_ALERT_THRESHOLD = CONFIG['thresholds']['cpu_threshold_percent']
QUERY_ALERT_THRESHOLD_MINUTES = CONFIG['thresholds']['query_alert_threshold_minutes']
QUERY_KILL_THRESHOLD_MINUTES = CONFIG['thresholds']['query_kill_threshold_minutes']
HEAP_CACHE_HIT_RATIO_MIN = CONFIG['thresholds']['heap_cache_hit_ratio_min']
INDEX_CACHE_HIT_RATIO_MIN = CONFIG['thresholds']['index_cache_hit_ratio_min']
TABLE_GROWTH_THRESHOLD_PERCENT = CONFIG['thresholds']['table_growth_threshold_percent']

# --- Configurações para Cooldown de Alertas (lidos do YAML) ---
ALERT_COOLDOWN_MINUTES = CONFIG['cooldown']['alert_cooldown_minutes']
LAST_ALERT_FILE = CONFIG['cooldown']['last_alert_file']
# Garante que o diretório do arquivo de cooldown exista
FileUtils.mkdir_p(File.dirname(LAST_ALERT_FILE))

# --- Configurações de Logging (lidos do YAML) ---
LOG_FILE = CONFIG['logging']['log_file']
LOG_LEVEL = CONFIG['logging']['log_level']
# Garante que o diretório do arquivo de log do script exista
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# --- Caminho dos Logs do PostgreSQL (lidos do YAML) ---
PG_LOG_PATH = CONFIG['postgresql_logs']['path']
PG_LOG_FILE_PATTERN = CONFIG['postgresql_logs']['file_pattern']

# --- Feature Toggles (lidos do YAML) ---
AUTO_KILL_ROGUE_PROCESSES = CONFIG['features']['auto_kill_rogue_processes']

# --- Funções de Conexão e Consulta ---
def connect_db
  PG.connect(host: DB_HOST, port: DB_PORT, dbname: DB_NAME, user: DB_USER, password: DB_PASSWORD)
rescue PG::Error => e
  message = "Erro ao conectar ao banco de dados: #{e.message}"
  send_email("ALERTA CRÍTICO: Falha na Conexão PostgreSQL", message, "DB_CONNECTION_ERROR_#{DB_NAME.upcase}")
  puts message
  exit 1
end

def execute_query(conn, query)
  conn.exec(query)
rescue PG::Error => e
  message = "Erro ao executar consulta: #{e.message}. Query: #{query.strip[0..100]}..."
  puts message
  nil
end

# --- Função de Envio de E-mail (COM COOLDOWN) ---
def send_email(subject, body, alert_type = "generic_alert")
  # Certifica-se de que o diretório para o arquivo de estado exista
  FileUtils.mkdir_p(File.dirname(LAST_ALERT_FILE)) unless File.directory?(File.dirname(LAST_ALERT_FILE))

  last_alert_times = File.exist?(LAST_ALERT_FILE) ? JSON.parse(File.read(LAST_ALERT_FILE)) : {}
  last_sent_time_str = last_alert_times[alert_type]
  last_sent_time = last_sent_time_str ? Time.parse(last_sent_time_str) : nil

  # Adiciona a data/hora local atual para o log
  current_local_time = Time.now.strftime('%d/%m/%Y %H:%M:%S')

  if last_sent_time && (Time.now - last_sent_time) < ALERT_COOLDOWN_MINUTES * 60
    puts "[#{current_local_time}] Alerta do tipo '#{alert_type}' suprimido devido ao cooldown de #{ALERT_COOLDOWN_MINUTES} minutos. Último envio: #{last_sent_time_str}."
    return # Não envia o e-mail se estiver em cooldown
  end

  puts "[#{current_local_time}] Enviando e-mail para #{RECEIVER_EMAIL} com o assunto: #{subject}"
  Mail.deliver do
    to RECEIVER_EMAIL
    from SENDER_EMAIL
    subject subject
    body body
  end
  puts "[#{current_local_time}] E-mail enviado com sucesso."

  # Atualiza o timestamp do último alerta APÓS o envio bem-sucedido
  last_alert_times[alert_type] = Time.now.iso8601
  File.write(LAST_ALERT_FILE, JSON.pretty_generate(last_alert_times))

rescue StandardError => e
  puts "[#{current_local_time}] Erro ao enviar e-mail: #{e.message}"
  puts "[#{current_local_time}] Verifique as configurações de SMTP e a senha do aplicativo (se estiver usando Gmail)."
  # Em caso de erro no envio, não atualizamos o timestamp para tentar novamente na próxima rodada
end

# --- MÉTODOS DE MONITORAMENTO DE ALTA FREQUÊNCIA (CRÍTICO) ---

def monitor_critical_metrics(conn)
  puts "\n--- Monitoramento de Alta Frequência (Crítico) ---"

  # Monitoramento de CPU com mpstat e Correlação
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

          if used_cpu_percent > $cpu_threshold_percent
            $alert_messages << "ALERTA: Alto uso de CPU detectado! Uso total: #{'%.2f' % used_cpu_percent}% (Limiar: #{$cpu_threshold_percent}%)."
            $alert_messages << "  Consultas ativas que podem estar contribuindo para o pico de CPU:"

            active_queries_for_cpu = execute_query(conn, %Q{
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
                $alert_messages << "    - PID: #{row['pid']}, Usuário: #{row['usename']}, Estado: #{row['state']}, Duração: #{row['query_duration']}, Query: #{row['query'].strip[0..100]}..."
              end
            else
              $alert_messages << "    Nenhuma consulta ativa significativa encontrada no PostgreSQL durante este período de alto CPU."
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


  # Conexões Ativas
  result_conn = execute_query(conn, "SELECT count(*) AS total_connections FROM pg_stat_activity;")
  if result_conn
    total_connections = result_conn.first['total_connections'].to_i
    result_max = execute_query(conn, "SHOW max_connections;")
    if result_max
      max_connections = result_max.first['max_connections'].to_i
      if total_connections >= max_connections * 0.9
        $alert_messages << "ALERTA CRÍTICO: Conexões (#{total_connections}) estão muito próximas do limite máximo (#{max_connections})!"
      end
    end
  end

  # Transações Longas / Bloqueios Ativos
  result_long_tx = execute_query(conn, %Q{
    SELECT
      pid, usename, application_name, query,
      age(now(), query_start) AS query_duration
    FROM pg_stat_activity
    WHERE state IN ('active', 'idle in transaction') AND age(now(), query_start) > INTERVAL '3 minutes'
    ORDER BY query_duration DESC;
  })

  if result_long_tx && result_long_tx.any?
    $alert_messages << "ALERTA CRÍTICO: Transações Muito Longas/Inativas Detectadas (>= 3 min):"
    result_long_tx.each do |row|
      $alert_messages << "  PID: #{row['pid']}, Usuário: #{row['usename']}, Duração: #{row['query_duration']}, Query: #{row['query'].strip[0..100]}..."
    end
  end

  # MELHORIA: Bloqueios Ativos Persistentes com detalhes (Tipo de Bloqueio, Tabela Envolvida)
  puts "\n--- Verificando Bloqueios Ativos Persistentes ---"
  result_locks = execute_query(conn, %Q{
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
    LEFT JOIN pg_class ON pg_class.oid = blocked_locks.relation -- Junta para pegar o nome da tabela
    WHERE NOT blocked_locks.granted AND age(now(), blocked_activity.query_start) > INTERVAL '30 seconds';
  })

  if result_locks && result_locks.any?
    $alert_messages << "ALERTA CRÍTICO: Bloqueios Ativos Persistentes Detectados (>= 30s):"
    result_locks.each do |row|
      $alert_messages << "  Bloqueado (PID: #{row['blocked_pid']}, User: #{row['blocked_user']}): #{row['blocked_query'].to_s.strip[0..100]}... (Duração: #{row['blocked_duration']})"
      $alert_messages << "  Bloqueador (PID: #{row['blocking_pid']}, User: #{row['blocking_user']}): #{row['blocking_query'].to_s.strip[0..100]}..."
      $alert_messages << "  Tipo de Bloqueio: #{row['lock_type']}, Modo: #{row['lock_mode']}"
      $alert_messages << "  Tabela Envolvida: #{row['locked_table_name'] || 'N/A'}" # Pode ser N/A se não for lock de relação
      $alert_messages << "  Tipo de Espera: #{row['wait_event_type']}, Evento: #{row['wait_event']}"
      $alert_messages << "  ---"
    end
  end


  # Wraparound do Transaction ID
  result_xid = execute_query(conn, %Q{
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
        $alert_messages << "ALERTA CRÍTICO: ID de transação para '#{row['datname']}' está MUITO PRÓXIMO do limite de wraparound! Idade atual: #{xid_age} (Limite: #{freeze_max_age})."
      end
    end
  end

  # Monitoramento de I/O com Iostat e Correlação
  begin
    iostat_output = `iostat -k #{$iostat_device} 1 2 2>/dev/null`
    if iostat_output && !iostat_output.empty?
      lines = iostat_output.split("\n")
      disk_line = lines.reverse.find { |line| line.strip.start_with?($iostat_device) }

      if disk_line
        parts = disk_line.split(/\s+/)
        # Garante que os índices existam antes de acessar
        rkbs_idx = parts.index($iostat_device) + 3 if parts.index($iostat_device)
        wkbs_idx = parts.index($iostat_device) + 4 if parts.index($iostat_device)

        rkbs = (rkbs_idx && parts[rkbs_idx]) ? parts[rkbs_idx].to_f : 0.0
        wkbs = (wkbs_idx && parts[wkbs_idx]) ? parts[wkbs_idx].to_f : 0.0

        total_kb_s = rkbs + wkbs

        if total_kb_s > $iostat_threshold_kb_s
          $alert_messages << "ALERTA: Alto I/O de disco em '#{$iostat_device}' detectado! Total: #{'%.2f' % (total_kb_s / 1024)} MB/s (Leitura: #{'%.2f' % (rkbs / 1024)} MB/s, Escrita: #{'%.2f' % (wkbs / 1024)} MB/s)."
          $alert_messages << "  Consultas ativas durante o pico de I/O:"

          active_queries_for_io = execute_query(conn, %Q{
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
              $alert_messages << "    - PID: #{row['pid']}, Usuário: #{row['usename']}, Estado: #{row['state']}, Duração: #{row['query_duration']}, Query: #{row['query'].to_s.strip[0..100]}..."
            end
          else
            $alert_messages << "    Nenhuma consulta ativa significativa encontrada no PostgreSQL durante este período de alto I/O."
          end
        end
      else
        puts "AVISO: Dispositivo '#{$iostat_device}' não encontrado na saída do iostat. Verifique o nome do dispositivo ou se o iostat está funcionando."
      end
    else
      puts "AVISO: iostat não retornou dados. Certifique-se de que está instalado e acessível no PATH."
    end
  rescue Errno::ENOENT
    puts "ERRO: Comando 'iostat' não encontrado. Certifique-se de que o pacote 'sysstat' está instalado."
  rescue StandardError => e
    puts "Erro ao executar iostat ou processar saída: #{e.message}"
  end

  # --- Validação e Morte de Consultas Longas ---
  puts "\n--- Verificando e Matando Consultas Excessivamente Longas ---"
  long_running_queries = execute_query(conn, %Q{
    SELECT
      pid, usename, application_name, client_addr, query,
      EXTRACT(EPOCH FROM (NOW() - query_start)) AS duration_seconds
    FROM pg_stat_activity
    WHERE state = 'active'
      AND usename != 'repack' -- Exclui o usuário 'repack'
      AND application_name NOT LIKE '%pg_repack%' -- Exclui aplicações de repack
      AND backend_type = 'client backend'
      AND NOW() - query_start > INTERVAL '#{$query_alert_threshold_minutes} minutes'
    ORDER BY duration_seconds DESC;
  })

  if long_running_queries && long_running_queries.any?
    $alert_messages << "ALERTA CRÍTICO: Consultas rodando há mais de #{$query_alert_threshold_minutes} minutos (e potencialmente encerradas):"
    long_running_queries.each do |row|
      duration_minutes = row['duration_seconds'].to_i / 60
      query_info = "  PID: #{row['pid']}, Usuário: #{row['usename']}, App: #{row['application_name']}, Cliente: #{row['client_addr']}, Duração: #{duration_minutes} min, Query: #{row['query'].to_s.strip[0..100]}..."
      $alert_messages << query_info

      if duration_minutes >= $query_kill_threshold_minutes
        puts "Tentando TERMINAR a consulta PID #{row['pid']} (duração: #{duration_minutes} min)..."
        terminate_result = execute_query(conn, "SELECT pg_terminate_backend(#{row['pid']});")
        if terminate_result && terminate_result.first['pg_terminate_backend'] == 't'
          $alert_messages << "    ---> SUCESSO: Consulta PID #{row['pid']} TERMINADA. <---"
          puts "Consulta PID #{row['pid']} terminada com sucesso."
        else
          $alert_messages << "    ---> ERRO: Falha ao TERMINAR a consulta PID #{row['pid']}. <---"
          puts "Falha ao terminar a consulta PID #{row['pid']}."
        end
      else
        puts "Consulta PID #{row['pid']} (duração: #{duration_minutes} min) será apenas alertada, ainda não será encerrada."
      end
    end
  else
    puts "Nenhuma consulta excessivamente longa encontrada."
  end

  # Cache Hit Ratio
  puts "\n--- Verificando Cache Hit Ratio ---"
  result_cache = execute_query(conn, %Q{
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
      if row['heap_hit_ratio'].to_f < 85
        $alert_messages << "AVISO: Heap Cache Hit Ratio baixo (#{row['heap_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas."
      end
      if row['idx_hit_ratio'].to_f < 85
        $alert_messages << "AVISO: Index Cache Hit Ratio baixo (#{row['idx_hit_ratio']}%). Considere ajustar shared_buffers ou otimizar consultas."
      end
    end
  end

  # --- NOVA MÉTRICA: Identificar Crescimento/Atividade Inesperada de Tabelas ---
  puts "\n--- Verificando Atividade Recente de Tabelas (Top 5 por Tamanho) ---"
  result_table_activity = execute_query(conn, %Q{
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
      $alert_messages << "INFO: Top 5 Tabelas por Tamanho com Atividade Recente (Desde último ANALYZE/VACUUM):"
      result_table_activity.each do |row|
          $alert_messages << "  - Tabela: #{row['schema_name']}.#{row['table_name']}, Tamanho: #{row['current_size']}"
          $alert_messages << "    Inserções: #{row['n_tup_ins']}, Atualizações: #{row['n_tup_upd']}, Deleções: #{row['n_tup_del']}"
          $alert_messages << "    Tuplas Vivas: #{row['n_live_tup']}, Tuplas Mortas: #{row['n_dead_tup']}"
          $alert_messages << "    Último Analyze: #{row['last_analyze'] || 'Nunca'}, Último Autovacuum: #{row['last_autovacuum'] || 'Nunca'}"
      end
  else
      puts "Nenhuma tabela de usuário encontrada para análise de atividade."
  end

  # --- NOVA MÉTRICA: Consultas com Uso Elevado de Temporary Files ---
  puts "\n--- Verificando Consultas com Uso Elevado de Temporary Files (Requer pg_stat_statements) ---"
  result_temp_files = execute_query(conn, %Q{
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
      $alert_messages << "ALERTA: Top 5 Consultas Usando Temporary Files (indicam necessidade de mais memória ou otimização):"
      result_temp_files.each do |row|
          $alert_messages << "  - Query: #{row['query'].to_s.strip[0..100]}..."
          $alert_messages << "    Blocos Lidos Temp: #{row['temp_blks_read']}, Blocos Escritos Temp: #{row['temp_blks_written']}"
          $alert_messages << "    Chamadas: #{row['calls']}, Tempo Total: #{'%.2f' % row['total_exec_time']}ms, Tempo Médio: #{'%.2f' % row['mean_exec_time']}ms"
      end
  else
      puts "Nenhuma consulta usando temporary files em grande volume detectada."
  end

  # --- NOVA MÉTRICA: Atividade de Checkpoint (I/O de Escrita) ---
  puts "\n--- Verificando Atividade de Checkpoint (I/O de Escrita) ---"
  result_bgwriter = execute_query(conn, %Q{
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
      # Se maxwritten_clean > 0, o background writer teve que parar, indicando I/O de escrita intenso.
      if row['maxwritten_clean'].to_i > 0
          $alert_messages << "ALERTA: O Background Writer atingiu o limite de buffers sujos (maxwritten_clean > 0). Isso indica I/O de escrita intenso. Considere ajustar wal_buffers, max_wal_size, checkpoint_timeout."
          $alert_messages << "  - Checkpoints Agendados: #{row['checkpoints_timed']}, Checkpoints Solicitados: #{row['checkpoints_req']}"
          $alert_messages << "  - Tempo de Escrita Checkpoint: #{row['checkpoint_write_time']}ms, Tempo de Sync Checkpoint: #{row['checkpoint_sync_time']}ms"
          $alert_messages << "  - Buffers Escritos por Checkpoint: #{row['buffers_checkpoint']}, Buffers Escritos por Backend: #{row['buffers_backend']}"
      else
        puts "Atividade de checkpoint normal (maxwritten_clean é 0)."
      end
  else
      puts "Não foi possível coletar métricas de pg_stat_bgwriter."
  end

end # Fim de monitor_critical_metrics


# MÉTODOS DE MONITORAMENTO DE MÉDIA FREQUÊNCIA (DESEMPENHO) ---
def monitor_performance_metrics(conn)
  puts "\n--- Monitoramento de Média Frequência (Desempenho) ---"

  # Autovacuum Ineficiente/Ausente (pode causar bloat/lentidão)
  result_autovac = execute_query(conn, %Q{
    SELECT
      relname,
      last_autovacuum,
      last_autoanalyze,
      autovacuum_count,
      analyze_count,
      n_dead_tup -- Adicionado para melhor contexto
    FROM pg_stat_all_tables
    WHERE schemaname = 'public' AND (last_autovacuum IS NULL OR last_autovacuum < NOW() - INTERVAL '7 days')
    and n_dead_tup > 0 -- Foca em tabelas com tuplas mortas
    ORDER BY autovacuum_count ASC NULLS FIRST;
  })

  if result_autovac && result_autovac.any?
    $alert_messages << "AVISO: Tabelas com autovacuum inativo ou muito antigo (últimos 5 com tuplas mortas):"
    result_autovac.each do |row|
      $alert_messages << "  Tabela: #{row['relname']}, Último AV: #{row['last_autovacuum'] || 'Nunca'}, Última AA: #{row['last_autoanalyze'] || 'Nunca'}, Tuplas Mortas: #{row['n_dead_tup']}"
    end
  end
end

# MÉTODOS DE MONITORAMENTO DE BAIXA FREQUÊNCIA (OTIMIZAÇÃO/TENDÊNCIAS) ---

def monitor_optimization_metrics(conn)
  puts "\n--- Monitoramento de Baixa Frequência (Otimização/Tendências) ---"

  # Espaço em Disco
  result_disk = execute_query(conn, "SELECT pg_size_pretty(pg_database_size('#{DB_NAME}')) AS db_size;")
  if result_disk
    db_size = result_disk.first['db_size']
    puts "Tamanho do banco de dados '#{DB_NAME}': #{db_size}"
    $alert_messages << "INFO: Tamanho total do banco de dados '#{DB_NAME}': #{db_size}."
  end

  # Índices Repetidos/Não Utilizados
  result_repeated_idx = execute_query(conn, %Q{
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
    $alert_messages << "INFORMAÇÃO: Índices Repetidos/Redundantes Encontrados (Top 3 por tamanho):"
    result_repeated_idx.each do |row|
      $alert_messages << "  Tabela: #{row['tbl']}, Tamanho Total: #{row['size']}, Índices: #{[row['idx1'], row['idx2']].compact.join(', ')}. Considere remover."
    end
  end

  result_unused_idx = execute_query(conn, %Q{
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
  AND pg_relation_size(psu.indexrelid) > 1000 * 1024 * 1024 -- Filtra por índices maiores que 1GB
  AND NOT pi.indisprimary -- Exclui primary key indexes
ORDER BY
  pg_relation_size(psu.indexrelid) desc
LIMIT 10;
  })

  if result_unused_idx && result_unused_idx.any?
    $alert_messages << "INFORMAÇÃO: Índices Não Utilizados Encontrados (Top 10 por tamanho, >1GB):"
    result_unused_idx.each do |row|
      $alert_messages << "  Tabela: #{row['table_name']}, Índice: #{row['index_name']}, Tamanho: #{row['index_size']}. Considere remover."
    end
  end

  # Top 10 Consultas Mais Lentas (requer pg_stat_statements)
  result_slow_queries = execute_query(conn, %Q{
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
    $alert_messages << "INFORMAÇÃO: Top 10 Consultas Mais Lentas (total_time):"
    result_slow_queries.each do |row|
      $alert_messages << "  Query: #{row['query'].to_s.strip[0..100]}..., Chamadas: #{row['calls']}, Tempo Total: #{'%.2f' % row['total_time']}ms, Tempo Médio: #{'%.2f' % row['mean_time']}ms, Linhas: #{row['rows']}"
    end
  end
end

# --- MÉTODOS DE TESTE DE CORRUPÇÃO (EXECUÇÃO SEMANAL) ---

def test_data_corruption
  puts "\n--- TESTE DE CORRUPÇÃO DE DADOS (pg_amcheck) ---"

  # 1. Verificação de Checksums de Blocos (status no DB)
  conn = nil
  begin
    conn = connect_db
    result_checksums = execute_query(conn, %Q{
      SELECT (SELECT setting FROM pg_settings WHERE name = 'data_checksums') as data_checksums_enabled;
    })

    if result_checksums && result_checksums.any?
      row = result_checksums.first
      if row['data_checksums_enabled'] == 'on'
        puts "Checksums de dados estão ATIVADOS."
        puts "Executando pg_amcheck --check-relations --check-indexes..."

        # Construir a string de conexão para pg_amcheck
        pg_amcheck_conn_string = "-h #{DB_HOST} -p #{DB_PORT} -U #{DB_USER} -d #{DB_NAME}"

        # Executa pg_amcheck e captura a saída
        # Importante: Passar a senha via PGPASSWORD para evitar que ela apareça na linha de comando do ps/top
        command = "PGPASSWORD=#{DB_PASSWORD} pg_amcheck #{pg_amcheck_conn_string} --check-relations --check-indexes --progress 2>&1"
        puts "Comando a ser executado: pg_amcheck #{pg_amcheck_conn_string.gsub(DB_PASSWORD, '********')} --check-relations --check-indexes --progress" # Para logar sem a senha

        amcheck_output = `#{command}`
        amcheck_exit_status = $?.exitstatus # Captura o status de saída do comando

        puts "Saída do pg_amcheck:\n#{amcheck_output}"

        if amcheck_exit_status == 0
          $alert_messages << "INFO: pg_amcheck executado com sucesso. Nenhuma corrupção de dados ou índice detectada."
        else
          $alert_messages << "ALERTA CRÍTICO: pg_amcheck detectou PROBLEMAS de corrupção ou falhou! Saída:\n#{amcheck_output}"
          $alert_messages << "Status de saída do pg_amcheck: #{amcheck_exit_status}. Verifique os logs para detalhes."
        end

      else
        puts "Checksums de dados estão DESATIVADOS."
        $alert_messages << "AVISO: Checksums de dados estão DESATIVADOS. A detecção de corrupção com pg_amcheck é menos eficaz sem eles. Recomenda-se ativar checksums (requer reinitdb e PERDA DE DADOS)."
      end
    else
      puts "Erro ao verificar o status dos checksums no banco de dados."
      $alert_messages << "ERRO: Falha ao verificar o status dos checksums no banco de dados."
    end
  rescue PG::Error => e
    $alert_messages << "ERRO DE BANCO DE DADOS ao tentar verificar checksums: #{e.message}"
  rescue Errno::ENOENT
    $alert_messages << "ERRO: Comando 'pg_amcheck' não encontrado. Certifique-se de que o pacote 'postgresql-contrib' ou similar está instalado."
  rescue StandardError => e
    $alert_messages << "ERRO NO SCRIPT ao executar pg_amcheck: #{e.message}\n#{e.backtrace.join("\n")}"
  ensure
    conn.close if conn
  end

  # 2. Consultas de Sanidade (Exemplo Básico - ADAPTAR PARA SUA ESTRUTURA!)
  conn = nil
  begin
    conn = connect_db
    puts "\n--- 2. Consultas de Sanidade Customizadas (ADAPTE PARA SUA ESTRUTURA!) ---"
    # Exemplo MUITO SIMPLES (ADAPTAR!)
    # Substitua 'sua_tabela_critica' por uma tabela real e 'valor_esperado' por sua lógica
    result_count = execute_query(conn, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
    if result_count
      count = result_count.first['count'].to_i
      puts "Contagem de tabelas públicas: #{count}"
      if count < 5 # Exemplo de uma regra de sanidade: menos de 5 tabelas públicas é um problema
        $alert_messages << "ALERTA: Número de tabelas públicas inesperadamente baixo (#{count}). Verifique a integridade do schema."
      else
        puts "Contagem de tabelas públicas está dentro do esperado."
      end
    else
      puts "Erro ao executar consulta de contagem em information_schema.tables."
      $alert_messages << "ERRO: Falha ao executar consulta de sanidade: Contagem de tabelas públicas."
    end
  rescue PG::Error => e
    $alert_messages << "ERRO DE BANCO DE DADOS em consultas de sanidade customizadas: #{e.message}"
  ensure
    conn.close if conn
  end

  puts "\n--- Lembre-se de ADAPTAR as consultas de sanidade para seu ambiente! ---"
end

# --- NOVO: MÉTODO PARA SALVAR HISTÓRICO DE TAMANHO DE TABELAS (EXECUÇÃO DIÁRIA) ---

def save_table_size_history
  puts "\n--- Salvando Histórico de Tamanho das Tabelas ---"
  conn = nil
  begin
    conn = connect_db

    # Garante que o schema e a tabela existam
    conn.exec("CREATE SCHEMA IF NOT EXISTS manutencao;")
    conn.exec(%q{
      CREATE TABLE IF NOT EXISTS manutencao.size_table_history (
        data_coleta TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        schema_name TEXT,
        table_name TEXT,
        table_size_bytes BIGINT
      );
    })

    # Insere os tamanhos das tabelas no histórico
    conn.exec(%q{
      INSERT INTO manutencao.size_table_history (data_coleta, schema_name, table_name, table_size_bytes)
      SELECT
        NOW(),
        table_schema,
        table_name,
        pg_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name))
      FROM information_schema.tables
      WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'manutencao') -- Exclui schemas do sistema e o próprio schema de manutenção
      AND table_type = 'BASE TABLE';
    })

    puts "Tamanhos das tabelas salvos em manutencao.size_table_history com sucesso."
    $alert_messages << "INFO: Histórico de tamanho das tabelas atualizado com sucesso."
  rescue PG::Error => e
    puts "Erro ao salvar tamanhos das tabelas: #{e.message}"
    $alert_messages << "ALERTA: Falha ao salvar o histórico de tamanho das tabelas: #{e.message}"
  ensure
    conn.close if conn
  end
end

# --- Execução Principal com Frequências (COM COOLDOWN) ---
def run_monitor(frequency_level)
  # O teste de corrupção e o histórico de tamanhos lidam com suas próprias conexões,
  # para que possam ser executados independentemente (e.g., com PGPASSWORD para pg_amcheck).
  conn = nil
  begin
    alert_type_for_email = "GENERIC_MONITORING_ALERT_#{DB_NAME.upcase}" # Tipo padrão para casos não categorizados

    # Só conecta ao DB no início para os níveis que precisam de uma conexão persistente
    if ['high', 'medium', 'low'].include?(frequency_level)
      conn = connect_db
    end

    case frequency_level
    when 'high'
      puts "Executando monitoramento de ALTA frequência..."
      monitor_critical_metrics(conn)
      alert_type_for_email = "HIGH_FREQ_ALERTS_#{DB_NAME.upcase}" # Categoria para alertas de alta frequência
    when 'medium'
      puts "Executando monitoramento de MÉDIA frequência..."
      monitor_performance_metrics(conn)
      alert_type_for_email = "MEDIUM_FREQ_ALERTS_#{DB_NAME.upcase}" # Categoria para alertas de média frequência
    when 'low'
      puts "Executando monitoramento de BAIXA frequência..."
      monitor_optimization_metrics(conn)
      alert_type_for_email = "LOW_FREQ_ALERTS_#{DB_NAME.upcase}" # Categoria para alertas de baixa frequência
    when 'corruption_test'
      puts "Executando TESTE DE CORRUPÇÃO DE DADOS (pg_amcheck e Sanidade Customizada)..."
      test_data_corruption
      alert_type_for_email = "CORRUPTION_TEST_ALERTS_#{DB_NAME.upcase}" # Categoria para alertas de corrupção
    when 'table_size_history' # NOVO NÍVEL
      puts "Executando Salvamento do Histórico de Tamanho das Tabelas..."
      save_table_size_history
      alert_type_for_email = "TABLE_SIZE_HISTORY_INFO_#{DB_NAME.upcase}" # Categoria para informações de histórico
    else
      puts "Nível de frequência desconhecido: #{frequency_level}. Use 'high', 'medium', 'low', 'corruption_test' ou 'table_size_history'."
      exit 1
    end

    if $alert_messages.empty?
      puts "Status do PostgreSQL para '#{frequency_level}' frequência: OK. Nenhum alerta detectado."
      # Não enviar e-mail se não houver alertas
    else
      subject = "ALERTA [#{frequency_level.upcase}]: Problemas/Informações no PostgreSQL - #{DB_NAME}"
      full_alert_body = "Monitoramento #{frequency_level.upcase} em #{Time.now.strftime('%d/%m/%Y %H:%M:%S')} (Goiânia, GO, Brasil) detectou os seguintes problemas/informações:\n\n"
      $alert_messages.each do |msg|
        full_alert_body << "- #{msg}\n"
      end
      # Chame send_email com o tipo de alerta específico baseado na frequência
      send_email(subject, full_alert_body, alert_type_for_email)
    end

  rescue StandardError => e
    current_local_time = Time.now.strftime('%d/%m/%Y %H:%M:%S')
    error_message = "[#{current_local_time}] Ocorreu um erro inesperado durante o monitoramento #{frequency_level}: #{e.message}\n#{e.backtrace.join("\n")}"
    send_email("ALERTA CRÍTICO: Erro no Script de Monitoramento PostgreSQL", error_message, "SCRIPT_ERROR_#{DB_NAME.upcase}") # Tipo específico para erros de script
    puts error_message
  ensure
    conn.close if conn && !conn.finished? # Fecha a conexão se ela foi aberta e não está fechada
  end
end

# Captura o argumento da linha de comando para definir a frequência
frequency = ARGV[0] || 'high'
run_monitor(frequency)
