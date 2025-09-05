# config/puma.rb
#!/usr/bin/env puma

# Puma configuration for pg_monitor metrics server

# The directory to operate out of.
directory '/app'

# Environment
environment ENV.fetch('RACK_ENV', 'production')

# Bind to all interfaces
bind 'tcp://0.0.0.0:9394'

# Logging
stdout_redirect '/var/log/pg_monitor/puma.log', '/var/log/pg_monitor/puma_error.log', true

# Daemonize the server into the background
# daemonize false

# Store the pid of the server in the file
pidfile '/tmp/pg_monitor/puma.pid'

# Configure "min" to be the minimum number of threads to use to answer
# requests and "max" the maximum.
threads_count = ENV.fetch('PUMA_THREADS', 2).to_i
threads threads_count, threads_count

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Preload the application before forking worker processes
preload_app!

# Worker configuration
workers ENV.fetch('PUMA_WORKERS', 1).to_i

# Use the `preload_app!` method when specifying a `workers` number.
on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
