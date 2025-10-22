#!/usr/bin/env ruby
# pg_monitor.rb - Entry point for PostgreSQL monitoring

# Load environment variables from .env file
env_file = File.join(__dir__, '.env')
if File.exist?(env_file)
  puts "📋 Loading environment variables from .env..."
  File.readlines(env_file).each do |line|
    line = line.strip
    # Skip empty lines and comments
    next if line.empty? || line.start_with?('#')
    
    # Parse key=value
    key, value = line.split('=', 2)
    next unless key && value
    
    # Clean key and value
    key = key.strip
    value = value.strip
    
    # Remove quotes from value (both single and double)
    value = value.gsub(/^['"]|['"]$/, '')
    
    # Set environment variable
    ENV[key] = value
  end
  puts "✅ Environment variables loaded from .env"
else
  puts "⚠️  Warning: .env file not found. Using system environment variables."
end

require_relative 'lib/pg_monitor'

# Parse command line arguments
frequency_level = ARGV[0] || 'high'
config_path = ARGV[1] # Optional config path

# Validate frequency level
valid_frequencies = %w[high medium low daily_log_scan weekly_login_summary table_size_history corruption_test]
unless valid_frequencies.include?(frequency_level)
  puts "Usage: ruby pg_monitor.rb [frequency] [config_path]"
  puts "  frequency: #{valid_frequencies.join(', ')}"
  puts "  config_path: optional path to config file (default: config/pg_monitor_config.yml)"
  exit 1
end

begin
  # Initialize monitor
  monitor = PgMonitor::Monitor.new(config_path)
  
  # Run monitoring
  monitor.run(frequency_level)
  
  puts "✅ Monitoring completed successfully for frequency: #{frequency_level}"
rescue => e
  puts "❌ Error running pg_monitor: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
