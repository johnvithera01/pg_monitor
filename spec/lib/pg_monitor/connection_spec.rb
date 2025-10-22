# spec/lib/pg_monitor/connection_spec.rb
require 'spec_helper'

RSpec.describe PgMonitor::Connection do
  let(:config) { instance_double(PgMonitor::Config) }
  let(:logger) { instance_double(PgMonitor::Logger) }
  let(:connection) { described_class.new(config) }

  before do
    allow(config).to receive(:db_host).and_return('localhost')
    allow(config).to receive(:db_port).and_return(5432)
    allow(config).to receive(:db_name).and_return('testdb')
    allow(config).to receive(:db_user).and_return('testuser')
    allow(config).to receive(:db_password).and_return('testpass')
    allow(PgMonitor::Logger).to receive(:new).with(config).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:fatal)
    allow(logger).to receive(:debug)
  end

  describe '#initialize' do
    it 'creates a new connection instance' do
      expect(connection).to be_a(described_class)
    end

    it 'initializes with nil connection' do
      expect(connection.raw_connection).to be_nil
    end
  end

  describe '#connect' do
    let(:mock_pg_connection) { instance_double(PG::Connection) }

    before do
      allow(PG).to receive(:connect).and_return(mock_pg_connection)
      allow(mock_pg_connection).to receive(:status).and_return(PG::CONNECTION_OK)
    end

    it 'establishes a connection successfully' do
      result = connection.connect

      expect(PG).to have_received(:connect).with(
        host: 'localhost',
        port: 5432,
        dbname: 'testdb',
        user: 'testuser',
        password: 'testpass',
        connect_timeout: 10,
        application_name: 'pg_monitor'
      )
      expect(result).to eq(mock_pg_connection)
      expect(connection.raw_connection).to eq(mock_pg_connection)
    end

    it 'logs connection attempts' do
      connection.connect

      expect(logger).to have_received(:info).with(/Attempting database connection/)
    end

    it 'logs successful connection' do
      connection.connect

      expect(logger).to have_received(:info).with('Successfully connected to PostgreSQL')
    end

    context 'when connection fails' do
      before do
        call_count = 0
        allow(PG).to receive(:connect) do
          call_count += 1
          if call_count < described_class::MAX_RETRIES
            raise PG::ConnectionBad, 'Connection failed'
          else
            mock_pg_connection
          end
        end
      end

      it 'retries connection on failure' do
        connection.connect

        expect(PG).to have_received(:connect).exactly(described_class::MAX_RETRIES).times
        expect(logger).to have_received(:error).with(/Database connection failed/)
        expect(logger).to have_received(:info).with(/Retrying connection in 2 seconds/)
      end

      it 'raises ConnectionError after max retries' do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad, 'Connection failed')

        expect { connection.connect }
          .to raise_error(PgMonitor::ConnectionError, /Unable to connect to database/)
        expect(logger).to have_received(:fatal).with(/Failed to connect after 3 attempts/)
      end
    end
  end

  describe '#execute_query' do
    let(:mock_connection) { instance_double(PG::Connection) }
    let(:mock_result) { instance_double(PG::Result) }

    before do
      connection.instance_variable_set(:@conn, mock_connection)
      allow(mock_connection).to receive(:exec).and_return(mock_result)
      allow(mock_connection).to receive(:exec_params).and_return(mock_result)
      allow(mock_result).to receive(:ntuples).and_return(1)
    end

    it 'executes query without parameters' do
      result = connection.execute_query('SELECT 1')

      expect(mock_connection).to have_received(:exec).with('SELECT 1')
      expect(result).to eq(mock_result)
    end

    it 'executes query with parameters' do
      result = connection.execute_query('SELECT * FROM users WHERE id = $1', [1])

      expect(mock_connection).to have_received(:exec_params).with('SELECT * FROM users WHERE id = $1', [1])
      expect(result).to eq(mock_result)
    end

    it 'logs query execution time and results' do
      allow(Time).to receive(:now).and_return(0, 0.5) # 500ms execution time

      connection.execute_query('SELECT 1')

      expect(logger).to have_received(:debug).with(/Query executed successfully/)
    end

    context 'when not connected' do
      it 'raises ConnectionError' do
        connection.instance_variable_set(:@conn, nil)

        expect { connection.execute_query('SELECT 1') }
          .to raise_error(PgMonitor::ConnectionError, 'Not connected to database')
      end
    end

    context 'when query fails' do
      before do
        allow(mock_connection).to receive(:exec).and_raise(PG::UndefinedTable, 'relation "users" does not exist')
      end

      it 'raises QueryError for general query failures' do
        expect { connection.execute_query('SELECT * FROM users') }
          .to raise_error(PgMonitor::QueryError, /Query failed/)
      end

      it 'raises ConnectionError for connection issues' do
        allow(mock_connection).to receive(:exec).and_raise(PG::ConnectionBad, 'server closed the connection unexpectedly')

        expect { connection.execute_query('SELECT 1') }
          .to raise_error(PgMonitor::ConnectionError, /Database connection lost/)
      end

      it 'raises QueryTimeoutError for timeout issues' do
        allow(mock_connection).to receive(:exec).and_raise(PG::ConnectionBad, 'timeout expired')

        expect { connection.execute_query('SELECT 1') }
          .to raise_error(PgMonitor::QueryTimeoutError, /Query timeout/)
      end

      it 'logs query execution failure' do
        allow(mock_connection).to receive(:exec).and_raise(PG::UndefinedTable, 'relation "users" does not exist')

        begin
          connection.execute_query('SELECT * FROM users')
        rescue PgMonitor::QueryError
          # Expected
        end

        expect(logger).to have_received(:error).with(/Query execution failed/)
      end
    end
  end

  describe '#transaction' do
    let(:mock_connection) { instance_double(PG::Connection) }

    before do
      connection.instance_variable_set(:@conn, mock_connection)
      allow(mock_connection).to receive(:transaction).and_yield(mock_connection)
    end

    it 'executes transaction block successfully' do
      result = nil

      expect {
        result = connection.transaction { |conn| 'transaction_result' }
      }.not_to raise_error

      expect(result).to eq('transaction_result')
    end

    it 'logs transaction failure' do
      allow(mock_connection).to receive(:transaction).and_raise(PG::UniqueViolation, 'duplicate key value')

      expect {
        connection.transaction { |conn| 'test' }
      }.to raise_error(PgMonitor::TransactionError, /Transaction failed/)

      expect(logger).to have_received(:error).with(/Transaction failed/)
    end

    context 'when not connected' do
      it 'raises ConnectionError' do
        connection.instance_variable_set(:@conn, nil)

        expect { connection.transaction { |conn| 'test' } }
          .to raise_error(PgMonitor::ConnectionError, 'Not connected to database')
      end
    end
  end

  describe '#connected?' do
    it 'returns false when no connection' do
      expect(connection.connected?).to eq(false)
    end

    it 'returns false when connection finished' do
      mock_connection = instance_double(PG::Connection)
      allow(mock_connection).to receive(:status).and_return(PG::CONNECTION_OK)
      allow(mock_connection).to receive(:finished?).and_return(true)

      connection.instance_variable_set(:@conn, mock_connection)

      expect(connection.connected?).to eq(false)
    end

    it 'returns true when connection is active' do
      mock_connection = instance_double(PG::Connection)
      allow(mock_connection).to receive(:status).and_return(PG::CONNECTION_OK)
      allow(mock_connection).to receive(:finished?).and_return(false)

      connection.instance_variable_set(:@conn, mock_connection)

      expect(connection.connected?).to eq(true)
    end
  end

  describe '#close' do
    let(:mock_connection) { instance_double(PG::Connection) }

    before do
      allow(mock_connection).to receive(:close)
      allow(mock_connection).to receive(:finished?).and_return(false)
    end

    it 'closes active connection' do
      connection.instance_variable_set(:@conn, mock_connection)

      connection.close

      expect(mock_connection).to have_received(:close)
      expect(logger).to have_received(:info).with('Database connection closed')
    end

    it 'does not close finished connection' do
      allow(mock_connection).to receive(:finished?).and_return(true)
      connection.instance_variable_set(:@conn, mock_connection)

      connection.close

      expect(mock_connection).not_to have_received(:close)
    end

    it 'does nothing when no connection' do
      connection.close

      expect(logger).not_to have_received(:info)
    end
  end

  describe '#raw_connection' do
    it 'returns the underlying connection' do
      mock_connection = instance_double(PG::Connection)
      connection.instance_variable_set(:@conn, mock_connection)

      expect(connection.raw_connection).to eq(mock_connection)
    end
  end

  describe 'error classes' do
    it 'defines ConnectionError' do
      expect(PgMonitor::ConnectionError).to be < StandardError
    end

    it 'defines QueryError' do
      expect(PgMonitor::QueryError).to be < StandardError
    end

    it 'defines QueryTimeoutError' do
      expect(PgMonitor::QueryTimeoutError).to be < PgMonitor::QueryError
    end

    it 'defines TransactionError' do
      expect(PgMonitor::TransactionError).to be < StandardError
    end
  end
end
