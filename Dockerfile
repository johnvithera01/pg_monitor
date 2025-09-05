# Dockerfile
FROM ruby:3.1-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    tzdata \
    curl \
    bash

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install --without development test

# Copy application code
COPY . .

# Create directories for logs and temp files
RUN mkdir -p /var/log/pg_monitor /tmp/pg_monitor

# Create non-root user
RUN addgroup -g 1001 pgmonitor && \
    adduser -D -s /bin/bash -u 1001 -G pgmonitor pgmonitor && \
    chown -R pgmonitor:pgmonitor /app /var/log/pg_monitor /tmp/pg_monitor

USER pgmonitor

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9394/health || exit 1

# Default command
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# Expose Prometheus metrics port
EXPOSE 9394
