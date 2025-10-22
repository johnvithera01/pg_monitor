# spec/lib/pg_monitor/alert_sink_spec.rb
require 'spec_helper'

RSpec.describe PgMonitor::AlertSink do
  let(:config) { instance_double(PgMonitor::Config) }
  let(:alert_sink) { described_class.new(config) }

  before do
    allow(PgMonitor::Logger).to receive(:new).and_return(instance_double(PgMonitor::Logger))
  end

  describe '#initialize' do
    it 'creates an alert sink instance' do
      expect(alert_sink).to be_a(described_class)
    end
  end

  describe '#send_alert' do
    let(:alert) { PgMonitor::Alert.new(type: 'test', severity: 'high', subject: 'Test Alert', body: 'Test body') }

    it 'processes alert through all enabled processors' do
      # Mock processors
      email_processor = instance_double(described_class::EmailProcessor)
      slack_processor = instance_double(described_class::SlackProcessor)
      webhook_processor = instance_double(described_class::WebhookProcessor)
      prometheus_processor = instance_double(described_class::PrometheusProcessor)

      allow(described_class::EmailProcessor).to receive(:new).with(config).and_return(email_processor)
      allow(described_class::SlackProcessor).to receive(:new).with(config).and_return(slack_processor)
      allow(described_class::WebhookProcessor).to receive(:new).with(config).and_return(webhook_processor)
      allow(described_class::PrometheusProcessor).to receive(:new).with(config).and_return(prometheus_processor)

      # Configure processor behavior
      allow(email_processor).to receive(:enabled?).and_return(true)
      allow(slack_processor).to receive(:enabled?).and_return(false)
      allow(webhook_processor).to receive(:enabled?).and_return(false)
      allow(prometheus_processor).to receive(:enabled?).and_return(true)

      allow(email_processor).to receive(:process).with(alert)
      allow(prometheus_processor).to receive(:process).with(alert)

      alert_sink.send_alert(alert)

      expect(email_processor).to have_received(:process).with(alert)
      expect(prometheus_processor).to have_received(:process).with(alert)
      expect(slack_processor).not_to have_received(:process)
      expect(webhook_processor).not_to have_received(:process)
    end

    it 'handles processor exceptions gracefully' do
      email_processor = instance_double(described_class::EmailProcessor)
      allow(described_class::EmailProcessor).to receive(:new).with(config).and_return(email_processor)

      allow(email_processor).to receive(:enabled?).and_return(true)
      allow(email_processor).to receive(:process).and_raise(StandardError.new('Email failed'))

      expect { alert_sink.send_alert(alert) }.not_to raise_error
    end
  end
end

RSpec.describe PgMonitor::Alert do
  describe '#initialize' do
    it 'creates alert with valid parameters' do
      alert = described_class.new(
        type: 'cpu_high',
        severity: 'high',
        subject: 'High CPU Usage',
        body: 'CPU usage is above threshold'
      )

      expect(alert.type).to eq('cpu_high')
      expect(alert.severity).to eq(:high)
      expect(alert.subject).to eq('High CPU Usage')
      expect(alert.body).to eq('CPU usage is above threshold')
      expect(alert.timestamp).to be_a(Time)
    end

    it 'accepts context parameter' do
      context = { cpu_percent: 95, threshold: 80 }
      alert = described_class.new(
        type: 'cpu_high',
        severity: 'high',
        subject: 'High CPU Usage',
        body: 'CPU usage is above threshold',
        context: context
      )

      expect(alert.context).to eq(context)
    end

    it 'raises error for invalid severity' do
      expect {
        described_class.new(
          type: 'test',
          severity: 'invalid',
          subject: 'Test',
          body: 'Test'
        )
      }.to raise_error(ArgumentError, /Invalid severity: invalid/)
    end

    it 'converts string severity to symbol' do
      alert = described_class.new(
        type: 'test',
        severity: 'high',
        subject: 'Test',
        body: 'Test'
      )

      expect(alert.severity).to eq(:high)
    end
  end

  describe '#severity_color' do
    it 'returns correct color for low severity' do
      alert = described_class.new(type: 'test', severity: 'low', subject: 'Test', body: 'Test')
      expect(alert.severity_color).to eq('good')
    end

    it 'returns correct color for medium severity' do
      alert = described_class.new(type: 'test', severity: 'medium', subject: 'Test', body: 'Test')
      expect(alert.severity_color).to eq('warning')
    end

    it 'returns correct color for high severity' do
      alert = described_class.new(type: 'test', severity: 'high', subject: 'Test', body: 'Test')
      expect(alert.severity_color).to eq('danger')
    end

    it 'returns correct color for critical severity' do
      alert = described_class.new(type: 'test', severity: 'critical', subject: 'Test', body: 'Test')
      expect(alert.severity_color).to eq('danger')
    end
  end

  describe '#priority' do
    it 'returns correct priority for low severity' do
      alert = described_class.new(type: 'test', severity: 'low', subject: 'Test', body: 'Test')
      expect(alert.priority).to eq(1)
    end

    it 'returns correct priority for medium severity' do
      alert = described_class.new(type: 'test', severity: 'medium', subject: 'Test', body: 'Test')
      expect(alert.priority).to eq(2)
    end

    it 'returns correct priority for high severity' do
      alert = described_class.new(type: 'test', severity: 'high', subject: 'Test', body: 'Test')
      expect(alert.priority).to eq(3)
    end

    it 'returns correct priority for critical severity' do
      alert = described_class.new(type: 'test', severity: 'critical', subject: 'Test', body: 'Test')
      expect(alert.priority).to eq(4)
    end
  end

  describe '#to_h' do
    it 'returns alert as hash' do
      context = { cpu_percent: 95 }
      alert = described_class.new(
        type: 'cpu_high',
        severity: 'high',
        subject: 'High CPU Usage',
        body: 'CPU usage is above threshold',
        context: context
      )

      hash = alert.to_h

      expect(hash[:type]).to eq('cpu_high')
      expect(hash[:severity]).to eq(:high)
      expect(hash[:subject]).to eq('High CPU Usage')
      expect(hash[:body]).to eq('CPU usage is above threshold')
      expect(hash[:context]).to eq(context)
      expect(hash[:timestamp]).to eq(alert.timestamp.iso8601)
    end
  end

  describe 'SEVERITIES constant' do
    it 'defines all required severities' do
      expected_severities = {
        low: { color: 'good', priority: 1 },
        medium: { color: 'warning', priority: 2 },
        high: { color: 'danger', priority: 3 },
        critical: { color: 'danger', priority: 4 }
      }

      expect(described_class::SEVERITIES).to eq(expected_severities)
    end
  end
end
