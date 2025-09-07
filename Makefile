# Makefile
.PHONY: help install test lint clean build run stop logs setup docker-build docker-run

# Default target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dependencies
	bundle install

test: ## Run tests
	bundle exec rspec

test-coverage: ## Run tests with coverage
	COVERAGE=true bundle exec rspec

lint: ## Run linter
	bundle exec rubocop

lint-fix: ## Run linter and fix issues
	bundle exec rubocop -a

clean: ## Clean temporary files
	rm -rf tmp/
	rm -rf log/
	rm -rf coverage/

setup: ## Initial setup
	@echo "Setting up pg_monitor..."
	@cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml
	@echo "Please edit config/pg_monitor_config.yml with your settings"
	@echo "Set environment variables:"
	@echo "  export PG_USER='your_pg_user'"
	@echo "  export PG_PASSWORD='your_pg_password'"
	@echo "  export EMAIL_PASSWORD='your_email_password'"
	bundle install

# Docker targets
docker-build: ## Build Docker image
	docker build -t pg_monitor:latest .

docker-run: ## Run with Docker Compose
	docker-compose up -d

docker-stop: ## Stop Docker containers
	docker-compose down

docker-logs: ## Show Docker logs
	docker-compose logs -f

docker-shell: ## Get shell in container
	docker-compose exec pg_monitor bash

# Monitoring targets
monitor-high: ## Run high frequency monitoring once
	ruby pg_monitor.rb high

monitor-medium: ## Run medium frequency monitoring once
	ruby pg_monitor.rb medium

monitor-low: ## Run low frequency monitoring once
	ruby pg_monitor.rb low

monitor-security: ## Run security monitoring once
	ruby pg_monitor.rb daily_log_scan

# Prometheus metrics
metrics: ## Show current Prometheus metrics
	curl -s http://localhost:9394/metrics

health: ## Check health status
	curl -s http://localhost:9394/health

# Development
dev-setup: ## Setup development environment
	bundle install --with development test
	@echo "Development environment ready!"

dev-console: ## Start development console
	bundle exec pry -I lib -r pg_monitor

# Production
deploy: ## Deploy to production
	@echo "Deploying pg_monitor..."
	docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
	@echo "Deployment complete!"

backup-config: ## Backup configuration
	tar -czf pg_monitor_config_backup_$(shell date +%Y%m%d_%H%M%S).tar.gz config/

# Database operations
db-test-connection: ## Test database connection
	ruby -e "require_relative 'lib/pg_monitor'; config = PgMonitor::Config.new; conn = PgMonitor::Connection.new(config); conn.connect; puts 'Connection successful!'; conn.close"

# Testing targets
test-all: ## Run all tests
	./test_runner.sh

test-scenarios: ## Run test scenarios
	./scripts/test_scenarios.sh

test-integration: ## Run integration tests
	bundle exec rspec spec/integration/

test-quick: ## Quick test (syntax and basic functionality)
	ruby -c pg_monitor.rb && ruby -c lib/pg_monitor.rb && echo "✅ Syntax OK"
