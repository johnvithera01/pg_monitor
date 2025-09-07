# lib/pg_monitor/collectors/security_metrics.rb
require_relative 'base_collector'

module PgMonitor
  module Collectors
    class SecurityMetrics < BaseCollector
      def monitor
        scan_failed_logins
        generate_weekly_summary
      end

      private

      def scan_failed_logins
        return unless @config.pg_log_path && Dir.exist?(@config.pg_log_path)

        begin
          # Create schema and table for failed logins if they don't exist
          execute_query("CREATE SCHEMA IF NOT EXISTS pg_monitor;")
          execute_query(%q{
            CREATE TABLE IF NOT EXISTS pg_monitor.failed_logins (
              id SERIAL PRIMARY KEY,
              timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
              log_line TEXT,
              user_name TEXT,
              ip_address TEXT,
              error_message TEXT
            );
          })

          # Scan log files for failed login attempts
          log_files = Dir.glob(File.join(@config.pg_log_path, @config.pg_log_file_pattern))
          failed_logins_count = 0

          log_files.each do |log_file|
            File.foreach(log_file) do |line|
              if line.include?('FATAL') && line.include?('password authentication failed')
                # Extract information from log line
                timestamp_match = line.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/)
                user_match = line.match(/user "([^"]+)"/)
                ip_match = line.match(/client (\d+\.\d+\.\d+\.\d+)/)

                timestamp = timestamp_match ? timestamp_match[1] : Time.now.strftime('%Y-%m-%d %H:%M:%S')
                user_name = user_match ? user_match[1] : 'unknown'
                ip_address = ip_match ? ip_match[1] : 'unknown'

                # Insert into database
                execute_query(%q{
                  INSERT INTO pg_monitor.failed_logins (timestamp, log_line, user_name, ip_address, error_message)
                  VALUES ($1, $2, $3, $4, $5)
                }, [timestamp, line.strip, user_name, ip_address, 'password authentication failed'])

                failed_logins_count += 1
              end
            end
          end

          if failed_logins_count > 0
            add_alert("INFO: #{failed_logins_count} tentativas de login falhadas detectadas e registradas no banco de dados.")
          end

        rescue StandardError => e
          add_alert("ERRO: Falha ao escanear logs de segurança: #{e.message}")
        end
      end

      def generate_weekly_summary
        begin
          # Get failed logins from the last week
          result = execute_query(%q{
            SELECT 
              DATE(timestamp) as login_date,
              user_name,
              ip_address,
              COUNT(*) as failed_attempts
            FROM pg_monitor.failed_logins
            WHERE timestamp >= NOW() - INTERVAL '7 days'
            GROUP BY DATE(timestamp), user_name, ip_address
            ORDER BY login_date DESC, failed_attempts DESC;
          })

          if result && result.any?
            summary = "RESUMO SEMANAL DE TENTATIVAS DE LOGIN FALHADAS:\n\n"
            result.each do |row|
              summary += "Data: #{row['login_date']}, Usuário: #{row['user_name']}, IP: #{row['ip_address']}, Tentativas: #{row['failed_attempts']}\n"
            end
            add_alert(summary)
          else
            add_alert("INFO: Nenhuma tentativa de login falhada detectada na última semana.")
          end

        rescue StandardError => e
          add_alert("ERRO: Falha ao gerar resumo semanal de segurança: #{e.message}")
        end
      end
    end
  end
end
