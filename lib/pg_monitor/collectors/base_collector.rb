# lib/pg_monitor/collectors/base_collector.rb
module PgMonitor
  module Collectors
    class BaseCollector
      def initialize(connection, config, alert_messages)
        @connection = connection
        @config = config
        @alert_messages = alert_messages
      end

      def monitor
        raise NotImplementedError, "Subclasses must implement #monitor method"
      end

      protected

      def add_alert(message)
        @alert_messages << message
      end

      def execute_query(query, params = [])
        @connection.execute_query(query, params)
      end
    end
  end
end
