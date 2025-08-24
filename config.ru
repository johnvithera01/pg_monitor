require 'rack'
require 'prometheus/client'
require 'prometheus/middleware/exporter'
require_relative './lib/pg_monitor/metrics'


use Rack::Deflater


use Prometheus::Middleware::Exporter

# Healthcheck simples em /
run lambda { |env|
[200, { 'Content-Type' => 'text/plain' }, ["pg_monitor exporter ok\n"]]
}