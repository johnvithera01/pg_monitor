# lib/pg_monitor/connection.rb
require 'pg'

module PgMonitor
  class Connection
    MAX_RETRIES = 3
    RETRY_DELAY = 2

    def initialize(config)
      @config = config
      @conn = nil
      @logger = Logger.new(config)
    end

    def connect
      attempt = 0
      
      begin
        attempt += 1
        @logger.info("Attempting database connection (attempt #{attempt}/#{MAX_RETRIES})")
        
        @conn = PG.connect(
          host: @config.db_host,
          port: @config.db_port,
          dbname: @config.db_name,
          user: @config.db_user,
          password: @config.db_password,
          connect_timeout: 10,
          application_name: 'pg_monitor'
        )
        
        @logger.info("Successfully connected to PostgreSQL")
        @conn
        
      rescue PG::Error => e
        @logger.error("Database connection failed (attempt #{attempt}): #{e.message}")
        
        if attempt < MAX_RETRIES
          @logger.info("Retrying connection in #{RETRY_DELAY} seconds...")
          sleep(RETRY_DELAY)
          retry
        else
          @logger.fatal("Failed to connect after #{MAX_RETRIES} attempts")
          raise ConnectionError, "Unable to connect to database: #{e.message}"
        end
      end
    end

    def execute_query(query, params = [])
      raise ConnectionError, "Not connected to database" unless connected?
      
      start_time = Time.now
      
      begin
        if params.any?
          result = @conn.exec_params(query, params)
        else
          result = @conn.exec(query)
        end
        
        execution_time = ((Time.now - start_time) * 1000).round(2)
        @logger.debug("Query executed successfully", {
          execution_time_ms: execution_time,
          rows_affected: result.ntuples
        })
        
        result
        
      rescue PG::Error => e
        execution_time = ((Time.now - start_time) * 1000).round(2)
        @logger.error("Query execution failed", {
          error: e.message,
          execution_time_ms: execution_time,
          query_preview: query.strip[0..100]
        })
        
        # Re-raise specific PostgreSQL errors
        case e.message
        when /connection.*closed/i, /server closed the connection/i
          raise ConnectionError, "Database connection lost: #{e.message}"
        when /timeout/i
          raise QueryTimeoutError, "Query timeout: #{e.message}"
        else
          raise QueryError, "Query failed: #{e.message}"
        end
      end
    end

    def transaction
      raise ConnectionError, "Not connected to database" unless connected?
      
      begin
        @conn.transaction do |conn|
          yield conn
        end
      rescue PG::Error => e
        @logger.error("Transaction failed: #{e.message}")
        raise TransactionError, "Transaction failed: #{e.message}"
      end
    end

    def connected?
      @conn && @conn.status == PG::CONNECTION_OK
    end

    def close
      if @conn && !@conn.finished?
        @conn.close
        @logger.info("Database connection closed")
      end
    end

    def raw_connection
      @conn
    end

    private

    def validate_connection
      unless connected?
        @logger.warn("Connection validation failed, attempting reconnect")
        connect
      end
    end
  end

  class ConnectionError < StandardError; end
  class QueryError < StandardError; end
  class QueryTimeoutError < QueryError; end
  class TransactionError < StandardError; end
end
