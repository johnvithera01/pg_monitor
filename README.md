# pg_monitor v2.0

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Ruby](https://img.shields.io/badge/Ruby-2.7%2B-red.svg)](https://www.ruby-lang.org/)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)

## 🚀 Overview

`pg_monitor` is a robust and intelligent Ruby application designed for **proactive PostgreSQL monitoring and advanced security**. It automates the detection of performance, security, and integrity issues, sending detailed, contextualized alerts via multiple channels (email, Slack, webhooks), transforming reactive database management into a proactive strategy.

## ✨ New in v2.0

- **🏗️ Modular Architecture**: Completely refactored with proper separation of concerns
- **🔒 Enhanced Security**: No more hardcoded passwords, improved error handling
- **🐳 Docker Support**: Full containerization with Docker Compose
- **📊 Better Monitoring**: Enhanced Prometheus metrics and Grafana dashboards
- **🧪 Test Suite**: Comprehensive RSpec test coverage
- **🔄 CI/CD Ready**: GitHub Actions, RuboCop, and automated testing
- **📱 Multi-Channel Alerts**: Email, Slack, and custom webhooks
- **📝 Structured Logging**: JSON logging with contextual information
- **⚙️ Better Configuration**: Validation and environment-based settings

## 🤔 Why This Script? The Pains It Solves

As DBAs and SysAdmins, we've all been there:
* **Unexpected performance spikes:** CPU and I/O soaring, with no immediate clue as to the cause.
* **Stuck transactions and locks:** Bottlenecks that paralyze applications and demand urgent manual intervention.
* **Silent security threats:** Failed login attempts buried in logs, difficult to track manually.
* **Data corruption:** Every DBA's nightmare, with the integrity of your most valuable asset constantly at risk.
* **Unexplained slowness:** Doubts about inefficient indexes, misconfigured `autovacuum`, or unoptimized queries.
* **Sleepless nights:** Constant worry and alerts that arrive too late.

`pg_monitor` was created to alleviate these pains by providing essential visibility, automation, and peace of mind.

## ✨ Key Features

This script offers multiple monitoring levels and advanced capabilities:

* **Intelligent & Contextual Alerts (Level `high`):**
    * Monitors CPU and I/O, correlating with active processes and problematic queries.
    * Detects and alerts on excessive connections and `idle in transaction` sessions.
    * Monitors `Heap Cache Hit Ratio` and `Index Cache Hit Ratio` for insights into memory efficiency.
    * Checks transaction ID age to prevent the dreaded `Transaction ID wraparound`.
* **Smart Security Surveillance (Levels `daily_log_scan` & `weekly_login_summary`):**
    * **Daily Scan:** Analyzes PostgreSQL logs to detect and record *all* failed login attempts into a dedicated table in your database (`pg_monitor.failed_logins`).
    * **Weekly Summary:** Sends an email consolidating weekly failed login attempts by date, user, and unique IP, offering a clear overview of your security posture.
* **Data Corruption Defense (Level `corruption_test`):**
    * Integrates with `pg_amcheck` to verify data and index integrity, alerting immediately if anomalies are detected.
* **Optimization & Sanity Checks (Levels `medium` & `low`):**
    * **`medium`:** Alerts on inefficient autovacuum and suggests `VACUUM ANALYZE` for problematic tables.
    * **`low`:** Identifies unused/redundant indexes and the top 10 slowest queries in your database.
* **Strategic Automation:**
    * Ability to identify and **automatically terminate** processes that exceed predefined limits (e.g., long-running transactions), preventing database crashes. (Requires `query_kill_threshold_minutes` in config and `features.auto_kill_rogue_processes` to be `true`).
* **Table Size History (Level `table_size_history`):**
    * Saves a historical record of table sizes to track growth and plan optimizations, alerting on significant growth (configured via `table_growth_threshold_percent`).
* **Alert Cooldown:** Prevents alert floods by implementing a cooldown period before sending repeat alerts of the same type.

## ⚙️ Prerequisites

To use `pg_monitor`, you will need:

* **Ruby:** Version 2.5 or higher.
* **Ruby Gems:** `pg`, `json`, `time`, `mail`, `fileutils`, `yaml`. Install them via Bundler or manually:
    ```bash
    gem install pg json mail fileutils yaml
    ```
* **PostgreSQL Database Access:** A user with appropriate permissions.
* **Operating System Access:** For `mpstat` (for CPU) and `iostat` (for I/O), which typically come with the `sysstat` package (install if necessary: `sudo apt-get install sysstat` on Debian/Ubuntu).
* **`pg_amcheck`:** Tool for corruption verification (usually part of `postgresql-contrib` or installed separately).
* **SMTP Server:** For sending emails (configured via `pg_monitor_config.yml` and environment variables).

---

## 🚀 Quick Start

### ⚡ One-Line Install

---

## 📦 Installation

### Requirements
- Ruby >= 2.7
- Bundler
- PostgreSQL client (`libpq`)
- Prometheus (to scrape metrics)
- Grafana (to visualize dashboards)

### Setup

Clone the repository and install dependencies:
```bash
# Quick setup with interactive script
curl -sSL https://raw.githubusercontent.com/johnvithera01/pg_monitor/main/quick-start.sh | bash
```

Or download and run locally:

```bash
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
chmod +x quick-start.sh
./quick-start.sh
```

### 🐳 Docker (Recommended)

The fastest way to get pg_monitor running is with Docker:

```bash
# Clone the repository
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor

# Copy environment variables template
cp .env.example .env

# Edit .env with your database credentials
nano .env

# Start with Docker Compose (includes PostgreSQL, Prometheus, and Grafana)
make docker-run
```

Access the services:
- **Prometheus metrics**: http://localhost:9394/metrics
- **Prometheus UI**: http://localhost:9090
- **Grafana dashboards**: http://localhost:3000 (admin/admin)

### 📦 Traditional Installation

#### 1. Clone the Repository

```bash
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
```

#### 2. Install Dependencies

```bash
# Install Ruby dependencies
bundle install

# Or use the Makefile
make install
```

#### 3. Setup Configuration

```bash
# Copy configuration template
cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml

# Edit configuration file
nano config/pg_monitor_config.yml

# Set environment variables
export PG_USER="your_postgres_user"
export PG_PASSWORD="your_postgres_password"
export EMAIL_PASSWORD="your_email_app_password"
```

#### 4. Test Connection

```bash
# Test database connection
make db-test-connection

# Run a quick monitoring test
ruby pg_monitor.rb high
```

---

## 🐳 Docker Usage Examples

### Production Deployment

```bash
# Clone and setup
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Deploy with all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f pg_monitor
```

### Development Environment

```bash
# Start only pg_monitor and PostgreSQL
docker-compose up -d pg_monitor postgres

# Access container shell
docker-compose exec pg_monitor bash

# Run monitoring manually inside container
ruby pg_monitor.rb high
```

### Monitoring Existing PostgreSQL

If you have an existing PostgreSQL server:

```bash
# Edit docker-compose.yml to remove postgres service
# Update .env with your PostgreSQL connection details

# Start only monitoring services
docker-compose up -d pg_monitor prometheus grafana
```

### Custom Configuration

```bash
# Mount custom configuration
docker run -d \
  --name pg_monitor \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/logs:/var/log/pg_monitor \
  -e PG_USER=myuser \
  -e PG_PASSWORD=mypassword \
  -e EMAIL_PASSWORD=myemailpass \
  -p 9394:9394 \
  pg_monitor:latest
```

---

## 💻 Usage Examples

### Basic Monitoring Commands

```bash
# High frequency monitoring (every 2 minutes via cron)
ruby pg_monitor.rb high

# Medium frequency monitoring (every 30 minutes)
ruby pg_monitor.rb medium

# Low frequency monitoring (daily)
ruby pg_monitor.rb low

# Security log scanning
ruby pg_monitor.rb daily_log_scan

# Weekly security summary
ruby pg_monitor.rb weekly_login_summary

# Table size history tracking
ruby pg_monitor.rb table_size_history

# Data corruption testing
ruby pg_monitor.rb corruption_test
```

### Using Makefile Commands

```bash
# Setup development environment
make dev-setup

# Run tests
make test

# Check code quality
make lint

# Build Docker image
make docker-build

# Start all services
make docker-run

# View Prometheus metrics
make metrics

# Check health status
make health
```

### Monitoring with Docker

```bash
# Start monitoring stack
docker-compose up -d

# Run one-time monitoring check
docker-compose exec pg_monitor ruby pg_monitor.rb high

# View real-time logs
docker-compose logs -f pg_monitor

# Scale monitoring instances
docker-compose up -d --scale pg_monitor=2

# Stop all services
docker-compose down
```

### Integration Examples

#### Slack Integration

```bash
# Set Slack webhook in environment
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Restart container to pick up new environment
docker-compose restart pg_monitor
```

#### Custom Webhook Integration

```bash
# Set custom webhook URL
export WEBHOOK_URL="https://your-monitoring-system.com/alerts"

# The webhook will receive JSON payloads like:
# {
#   "alert_type": "high_cpu",
#   "severity": "critical",
#   "subject": "High CPU Usage Detected",
#   "body": "CPU usage is at 95%...",
#   "timestamp": "2025-09-05T10:30:00Z",
#   "database": {
#     "host": "localhost",
#     "name": "postgres"
#   },
#   "source": "pg_monitor"
# }
```

#### Prometheus + Grafana Setup

```bash
# Start full monitoring stack
docker-compose up -d

# Import Grafana dashboard
# 1. Go to http://localhost:3000
# 2. Login with admin/admin
# 3. Import dashboard from dashboards/pg_monitor_overview.json

# Query Prometheus metrics
curl http://localhost:9394/metrics | grep pgmon
```

---

## 📋 Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `PG_USER` | ✅ | PostgreSQL username | `postgres` |
| `PG_PASSWORD` | ✅ | PostgreSQL password | `mypassword` |
| `EMAIL_PASSWORD` | ✅ | Email app password | `abcd efgh ijkl mnop` |
| `SLACK_WEBHOOK_URL` | ❌ | Slack webhook for alerts | `https://hooks.slack.com/...` |
| `WEBHOOK_URL` | ❌ | Custom webhook endpoint | `https://api.example.com/alerts` |
| `GRAFANA_PASSWORD` | ❌ | Grafana admin password | `admin` |
| `RACK_ENV` | ❌ | Application environment | `production` |

---

## 🔧 Configuration Files

### Main Configuration: `config/pg_monitor_config.yml`

```yaml
database:
  host: "localhost"
  port: 5432
  name: "postgres"

email:
  sender_email: "monitor@yourcompany.com"
  receiver_email: "dba@yourcompany.com"
  smtp_address: "smtp.gmail.com"
  smtp_port: 587
  smtp_domain: "gmail.com"

thresholds:
  cpu_threshold_percent: 80
  heap_cache_hit_ratio_min: 95
  query_alert_threshold_minutes: 5
  alert_cooldown_minutes: 60
```

### Docker Compose Override

Create `docker-compose.override.yml` for custom settings:

```yaml
version: '3.8'

services:
  pg_monitor:
    environment:
      - CUSTOM_VAR=custom_value
    volumes:
      - /path/to/your/pg/logs:/var/lib/postgresql/data/log:ro
```

---

## 🚀 Production Deployment

### 1. Prepare Environment

```bash
# Create production directory
mkdir -p /opt/pg_monitor
cd /opt/pg_monitor

# Clone repository
git clone https://github.com/johnvithera01/pg_monitor.git .

# Setup environment
cp .env.example .env
nano .env  # Configure your settings
```

### 2. Deploy with Docker

```bash
# Build and start services
make docker-build
make docker-run

# Verify deployment
make health
curl http://localhost:9394/metrics
```

### 3. Setup Monitoring

```bash
# Configure log rotation
sudo cp crontab /etc/cron.d/pg_monitor

# Setup systemd service (optional)
sudo cp scripts/pg_monitor.service /etc/systemd/system/
sudo systemctl enable pg_monitor
sudo systemctl start pg_monitor
```

### 4. Backup Configuration

```bash
# Backup configuration
make backup-config

# Setup automated backups
echo "0 2 * * 0 cd /opt/pg_monitor && make backup-config" | sudo crontab -
```

---

## 🔍 Troubleshooting

### Common Issues

#### Connection Problems

```bash
# Test database connection
make db-test-connection

# Check if PostgreSQL is running
systemctl status postgresql

# Verify credentials
psql -h localhost -U $PG_USER -d postgres -c "SELECT version();"
```

#### Docker Issues

```bash
# Check container status
docker-compose ps

# View container logs
docker-compose logs pg_monitor

# Restart services
docker-compose restart

# Clean rebuild
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

#### Permission Issues

```bash
# Fix log directory permissions
sudo chown -R $USER:$USER /var/log/pg_monitor

# Fix application directory permissions
sudo chown -R $USER:$USER /opt/pg_monitor
```

#### Email Not Sending

```bash
# Check email configuration
grep -A 10 "email:" config/pg_monitor_config.yml

# Test SMTP connection
telnet smtp.gmail.com 587

# Verify app password (for Gmail)
# Use App Password, not regular password
```

### FAQ

**Q: How often should I run different monitoring levels?**
A: 
- `high`: Every 1-5 minutes (critical metrics)
- `medium`: Every 30-60 minutes (performance checks)
- `low`: Daily (maintenance tasks)
- `security`: Daily (log analysis)

**Q: Can I monitor multiple PostgreSQL instances?**
A: Yes, run separate pg_monitor instances with different configuration files:
```bash
ruby pg_monitor.rb high config/db1_config.yml
ruby pg_monitor.rb high config/db2_config.yml
```

**Q: How to reduce alert noise?**
A: Adjust cooldown settings in configuration:
```yaml
cooldown:
  alert_cooldown_minutes: 120  # Increase cooldown period
```

**Q: Can I use custom alert channels?**
A: Yes, set environment variables:
```bash
export SLACK_WEBHOOK_URL="your_slack_webhook"
export WEBHOOK_URL="your_custom_endpoint"
```

**Q: How to backup monitoring data?**
A: Use the backup command:
```bash
make backup-config
```

**Q: Performance impact on PostgreSQL?**
A: Minimal impact:
- Monitoring queries are optimized
- Configurable alert cooldowns prevent spam
- Resource usage is logged

---

## 📊 Metrics and Monitoring

### Prometheus Metrics

pg_monitor exports the following metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `pgmon_checks_total` | Counter | Total monitoring executions |
| `pgmon_alerts_total` | Counter | Total alerts generated |
| `pgmon_failed_logins_total` | Counter | Failed login attempts detected |
| `pgmon_slow_queries` | Gauge | Current slow query count |
| `pgmon_idle_in_tx` | Gauge | Idle in transaction sessions |
| `pgmon_oldest_xid_age` | Gauge | Age of oldest transaction ID |
| `pgmon_table_growth_pct` | Gauge | Table growth percentage |
| `pgmon_last_run_timestamp` | Gauge | Last execution timestamp |

### Grafana Dashboards

Import the included dashboard:
1. Go to Grafana (http://localhost:3000)
2. Click "+" → Import
3. Upload `dashboards/pg_monitor_overview.json`

### Custom Alerts

Create custom Prometheus alerts in `config/alertmanager.yml`:

```yaml
groups:
- name: pg_monitor
  rules:
  - alert: HighFailedLogins
    expr: increase(pgmon_failed_logins_total[5m]) > 10
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High number of failed PostgreSQL logins"
      description: "{{ $value }} failed logins in the last 5 minutes"
```

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone and setup development environment
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
make dev-setup

# Run tests
make test

# Check code quality
make lint

# Start development console
make dev-console
```

### Code Style

We use RuboCop for code formatting:

```bash
# Check style
make lint

# Auto-fix issues
make lint-fix
```

---

## 📝 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

## 🆘 Support

- **Documentation**: [GitHub Wiki](https://github.com/johnvithera01/pg_monitor/wiki)
- **Issues**: [GitHub Issues](https://github.com/johnvithera01/pg_monitor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/johnvithera01/pg_monitor/discussions)

---

## 🎯 Roadmap

- [ ] Web UI for configuration and monitoring
- [ ] Support for PostgreSQL clusters
- [ ] Machine learning-based anomaly detection
- [ ] Integration with more alerting systems
- [ ] Real-time streaming metrics
- [ ] Mobile app for alerts

---

*Made with ❤️ for the PostgreSQL community*
