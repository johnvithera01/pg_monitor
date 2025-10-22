# lib/pg_monitor/email_sender.rb
require 'mail'
require 'fileutils'
require 'json'

module PgMonitor
  class EmailSender
    def initialize(config)
      @config = config
      setup_mail_configuration
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
      
      begin
        # Save config to local variable to use inside block
        config = @config
        
        Mail.deliver do
          to config.receiver_email
          from config.sender_email
          subject subject
          body body
        end
        puts "[#{current_local_time}] E-mail enviado com sucesso."

        last_alert_times[alert_type] = Time.now.iso8601
        File.write(@config.last_alert_file, JSON.pretty_generate(last_alert_times))

      rescue StandardError => e
        puts "[#{current_local_time}] Erro ao enviar e-mail: #{e.message}"
        puts "[#{current_local_time}] Verifique as configurações de SMTP e a senha do aplicativo (se estiver usando Gmail)."
        raise EmailError, "Failed to send email: #{e.message}"
      end
    end

    def send_slack_alert(message, webhook_url = nil)
      webhook_url ||= ENV['SLACK_WEBHOOK_URL']
      return unless webhook_url

      require 'net/http'
      require 'uri'

      begin
        uri = URI.parse(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        request.body = {
          text: "🚨 pg_monitor Alert",
          attachments: [{
            color: 'danger',
            text: message,
            timestamp: Time.now.to_i
          }]
        }.to_json

        response = http.request(request)
        
        if response.code == '200'
          puts "Slack alert sent successfully"
        else
          puts "Failed to send Slack alert: #{response.code} - #{response.body}"
        end
      rescue StandardError => e
        puts "Error sending Slack alert: #{e.message}"
      end
    end

    def send_webhook_alert(payload, webhook_url = nil)
      webhook_url ||= ENV['WEBHOOK_URL']
      return unless webhook_url

      require 'net/http'
      require 'uri'

      begin
        uri = URI.parse(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json

        response = http.request(request)
        
        if response.code.to_i.between?(200, 299)
          puts "Webhook alert sent successfully"
        else
          puts "Failed to send webhook alert: #{response.code} - #{response.body}"
        end
      rescue StandardError => e
        puts "Error sending webhook alert: #{e.message}"
      end
    end

    private

    def setup_mail_configuration
      # Save config to local variable to use inside block
      config = @config
      
      Mail.defaults do
        delivery_method :smtp, {
          address: config.smtp_address,
          port: config.smtp_port,
          domain: config.smtp_domain,
          user_name: config.sender_email,
          password: config.sender_password,
          authentication: 'plain',
          enable_starttls_auto: true
        }
      end
    end
  end

  class EmailError < StandardError; end
end
