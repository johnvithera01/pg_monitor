# Encaminha alertas do pg_monitor para integrações (ex.: Protheus) com deduplicação simples.


require 'digest'
require 'time'
require_relative '../protheus_client'


module PgMonitor
class AlertSink
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