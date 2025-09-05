# lib/pg_monitor/alert_sink.rb
require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'time'
require_relative '../protheus_client'

module PgMonitor
  class AlertSink
    def initialize(config)
      @config = config
      @logger = Logger.new(config)
    end

    def send_alert(alert)
      processors = [
        EmailProcessor.new(@config),
        SlackProcessor.new(@config),
        WebhookProcessor.new(@config),
        PrometheusProcessor.new(@config)
      ]

      processors.each do |processor|
        next unless processor.enabled?
        
        begin
          processor.process(alert)
          @logger.info("Alert sent successfully via #{processor.class.name}")
        rescue => e
          @logger.error("Failed to send alert via #{processor.class.name}: #{e.message}")
        end
      end
    end

    private

    class BaseProcessor
      def initialize(config)
        @config = config
        @logger = Logger.new(config)
      end

      def enabled?
        false
      end

      def process(alert)
        raise NotImplementedError
      end
    end

    class EmailProcessor < BaseProcessor
      def enabled?
        @config.sender_email && @config.receiver_email
      end

      def process(alert)
        email_sender = EmailSender.new(@config)
        email_sender.send_alert_email(
          alert.subject,
          alert.body,
          alert.type
        )
      end
    end

    class SlackProcessor < BaseProcessor
      def enabled?
        ENV['SLACK_WEBHOOK_URL']
      end

      def process(alert)
        webhook_url = ENV['SLACK_WEBHOOK_URL']
        
        payload = {
          text: alert.subject,
          attachments: [{
            color: alert.severity_color,
            fields: [
              {
                title: "Database",
                value: @config.db_name,
                short: true
              },
              {
                title: "Host",
                value: @config.db_host,
                short: true
              },
              {
                title: "Details",
                value: alert.body,
                short: false
              }
            ],
            footer: "pg_monitor",
            ts: Time.now.to_i
          }]
        }

        send_webhook(webhook_url, payload)
      end

      private

      def send_webhook(url, payload)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json

        response = http.request(request)
        
        unless response.is_a?(Net::HTTPSuccess)
          raise "Slack webhook failed: #{response.code} #{response.message}"
        end
      end
    end

    class WebhookProcessor < BaseProcessor
      def enabled?
        ENV['WEBHOOK_URL']
      end

      def process(alert)
        webhook_url = ENV['WEBHOOK_URL']
        
        payload = {
          alert_type: alert.type,
          severity: alert.severity,
          subject: alert.subject,
          body: alert.body,
          timestamp: Time.now.iso8601,
          database: {
            host: @config.db_host,
            name: @config.db_name
          },
          source: 'pg_monitor'
        }

        send_webhook(webhook_url, payload)
      end

      private

      def send_webhook(url, payload)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-PG-Monitor-Version'] = PgMonitor::VERSION
        request.body = payload.to_json

        response = http.request(request)
        
        unless response.is_a?(Net::HTTPSuccess)
          raise "Webhook failed: #{response.code} #{response.message}"
        end
      end
    end

    class PrometheusProcessor < BaseProcessor
      def enabled?
        true # Always enabled to update Prometheus metrics
      end

      def process(alert)
        Metrics.bump_alerts!(1)
        
        # Update specific metrics based on alert type
        case alert.type
        when /security/i
          Metrics.bump_failed_logins!(1) if alert.type.include?('login')
        end
      end
    end
  end

  class Alert
    attr_reader :type, :severity, :subject, :body, :timestamp, :context

    SEVERITIES = {
      low: { color: 'good', priority: 1 },
      medium: { color: 'warning', priority: 2 },
      high: { color: 'danger', priority: 3 },
      critical: { color: 'danger', priority: 4 }
    }.freeze

    def initialize(type:, severity:, subject:, body:, context: {})
      @type = type
      @severity = severity.to_sym
      @subject = subject
      @body = body
      @context = context
      @timestamp = Time.now
      
      validate_severity!
    end

    def severity_color
      SEVERITIES[@severity][:color]
    end

    def priority
      SEVERITIES[@severity][:priority]
    end

    def to_h
      {
        type: @type,
        severity: @severity,
        subject: @subject,
        body: @body,
        context: @context,
        timestamp: @timestamp.iso8601
      }
    end

    private

    def validate_severity!
      unless SEVERITIES.key?(@severity)
        raise ArgumentError, "Invalid severity: #{@severity}. Must be one of: #{SEVERITIES.keys.join(', ')}"
      end
    end
  end
# store: { hash => epoch_ts }
def initialize(config)
@config = config || {}
@store = {}
@ttl_seconds = (@config.dig(:alerting, :dedup_ttl_minutes) || 60).to_i * 60
@protheus_enabled = !!@config.dig(:features, :protheus_integration)
if @protheus_enabled
@protheus = ProtheusClient.from_config(@config[:protheus])
@endpoint = @config.dig(:alerting, :protheus_endpoint) || '/rest/MI/ZZALERTA'
end
end


def notify(alert)
# alert: { severity:, category:, description:, db_name:, host:, labels:{}, metrics:{}, grafana_url: }
key = Digest::SHA256.hexdigest(alert.to_a.sort_by(&:first).to_s)
now = Time.now.to_i
gc!(now)
return :skipped if @store[key] && (now - @store[key] < @ttl_seconds)


if @protheus_enabled
resp = @protheus.create_incident(@endpoint, alert)
# Poderia checar resp.code e tratar erros/retry
end


@store[key] = now
:sent
rescue => e
warn "[AlertSink] erro ao notificar: #{e.class}: #{e.message}"
:error
end


private


def gc!(now)
@store.delete_if { |_k, ts| now - ts > @ttl_seconds }
end
end
end