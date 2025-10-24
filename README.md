# pg_monitor v2.0

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Ruby](https://img.shields.io/badge/Ruby-3.2.2-red.svg)](https://www.ruby-lang.org/)
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
- **🚀 Automated Setup**: One-command installation script
- **💀 Auto-Kill Rogue Processes**: Automatically terminate long-running queries
- **📧 Smart Email Alerts**: Contextual alerts with SMTP authentication
- **🔧 rbenv Integration**: Proper Ruby version management

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
    * **Configurable Kill Thresholds**: Automatically kill queries after 60 minutes (configurable) to prevent database locks.
    * **Smart Alerting**: Contextual alerts with proper SMTP authentication and Gmail App Password support.
* **Table Size History (Level `table_size_history`):**
    * Saves a historical record of table sizes to track growth and plan optimizations, alerting on significant growth (configured via `table_growth_threshold_percent`).
* **Alert Cooldown:** Prevents alert floods by implementing a cooldown period before sending repeat alerts of the same type.

## ⚙️ Prerequisites

To use `pg_monitor`, you will need:

* **Ruby:** Version 3.2.2 (automatically installed via rbenv).
* **Ruby Gems:** `pg`, `mail`, `prometheus-client`, `rack`, `puma`, `oauth`. Automatically installed via Bundler.
* **PostgreSQL Database Access:** A user with appropriate permissions.
* **Operating System Access:** For `mpstat` (for CPU) and `iostat` (for I/O), which typically come with the `sysstat` package (install if necessary: `sudo apt-get install sysstat` on Debian/Ubuntu).
* **`pg_amcheck`:** Tool for corruption verification (usually part of `postgresql-contrib` or installed separately).
* **SMTP Server:** For sending emails (Gmail App Password recommended).

---

## 🚀 Quick Start

### ⚡ One-Line Install (Automated Setup)

The fastest way to get pg_monitor running is with our automated setup script:

```bash
# 1. Install PostgreSQL first (if not already installed)
sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib

# 2. Clone and run automated setup (installs everything automatically)
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
./setup_pg_monitor.sh
```

The automated script will:
- ✅ Install rbenv and Ruby 3.2.2
- ✅ Install all required dependencies
- ✅ Configure environment variables interactively
- ✅ Setup SMTP settings for email alerts
- ✅ Test the installation
- ✅ Configure cron jobs (optional)

**⏱️ Installation time: 2-5 minutes**

---

## 📦 Installation

**⚠️ IMPORTANTE:** pg_monitor é uma ferramenta de **monitoramento**. PostgreSQL deve estar **instalado externamente**.

### 📚 Guias de Instalação

- 🐳 **[Instalação Docker](DOCKER_INSTALL.md)** - Recomendado para ambientes containerizados
- 💻 **[Instalação Tradicional](README_INSTALACAO.md)** - Para instalação direta no servidor

### Requirements
- Ruby >= 3.2.2 (automatically installed)
- Bundler (automatically installed)
- PostgreSQL client (`libpq`)
- Prometheus (to scrape metrics)
- Grafana (to visualize dashboards)

### Setup

Clone the repository and install dependencies:

```bash
# Quick setup with automated script (RECOMMENDED)
./setup_pg_monitor.sh
```

Or install manually:

```bash
# Install Ruby dependencies via rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
bundle install
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
| `EMAIL_PASSWORD` | ✅ | Gmail App Password (without spaces) | `ajrvugbjdnwwzloc` |
| `SLACK_WEBHOOK_URL` | ❌ | Slack webhook for alerts | `https://hooks.slack.com/...` |
| `WEBHOOK_URL` | ❌ | Custom webhook endpoint | `https://api.example.com/alerts` |
| `GRAFANA_PASSWORD` | ❌ | Grafana admin password | `admin` |
| `RACK_ENV` | ❌ | Application environment | `production` |

**Note:** Gmail App Password should be entered **without spaces**. The setup script will automatically remove any spaces for you.

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
  query_kill_threshold_minutes: 60
  alert_cooldown_minutes: 60

features:
  auto_kill_rogue_processes: true

logging:
  log_file: "/var/log/pg_monitor/pg_monitor.log"
  log_level: "info"
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

#### Ruby/rbenv Issues

```bash
# If you get "cannot load such file -- mail" error
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"

# Install missing gems
bundle install

# Or install manually
gem install mail prometheus-client pg rack puma oauth --no-document
```

#### Setup Script Issues

```bash
# If setup script fails, run manually
cd pg_monitor

# 1. Install dependencies
sudo apt-get install -y git curl autoconf bison build-essential libssl-dev \
    libyaml-dev libreadline6-dev zlib1g-dev libgmp-dev libncurses5-dev \
    libffi-dev libgdbm-dev libdb-dev uuid-dev libreadline-dev sysstat

# 2. Install rbenv and Ruby
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# 3. Load rbenv and install Ruby
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
rbenv install 3.2.2
rbenv global 3.2.2

# 4. Install gems and run setup
gem install bundler
bundle install
./setup_pg_monitor.sh
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
# 1. Go to https://myaccount.google.com/apppasswords
# 2. Generate App Password for "Mail"
# 3. Use password WITHOUT spaces (e.g., 'abcd' not 'a b c d')
# 4. Update EMAIL_PASSWORD in .env file

# Test email functionality
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
ruby -e "
require 'mail'
Mail.defaults do
  delivery_method :smtp, {
    address: 'smtp.gmail.com',
    port: 587,
    user_name: 'your-email@gmail.com',
    password: 'your-app-password',
    authentication: 'plain',
    enable_starttls_auto: true
  }
end
Mail.deliver do
  to 'test@example.com'
  from 'your-email@gmail.com'
  subject 'Test'
  body 'Test message'
end
puts 'Email sent successfully!'
"
```

#### Common Email Issues:
- **535 Authentication Error**: Wrong app password or 2FA not enabled
- **SMTP Port Error**: Make sure `smtp_port: 587` in config (not 5432)
- **App Password with Spaces**: Gmail App Passwords should not have spaces

### FAQ

**Q: How often should I run different monitoring levels?**
A: 
- `high`: Every 1-5 minutes (critical metrics)
- `medium`: Every 30-60 minutes (performance checks)
- `low`: Daily (maintenance tasks)
- `security`: Daily (log analysis)

**Q: How does auto-kill of idle sessions work?**
A: pg_monitor can automatically terminate long-running queries:
```yaml
# In config/pg_monitor_config.yml
thresholds:
  query_alert_threshold_minutes: 5   # Alert after 5 minutes
  query_kill_threshold_minutes: 60   # Kill after 60 minutes

features:
  auto_kill_rogue_processes: true     # Enable auto-kill
```
- Detects queries running > 5 minutes
- Sends email alert
- Automatically kills queries after 60 minutes using `pg_terminate_backend()`
- Prevents database locks and performance issues

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

- [x] **Automated Setup Script** - One-command installation
- [x] **Auto-Kill Rogue Processes** - Terminate long-running queries automatically
- [x] **Enhanced SMTP Authentication** - Gmail App Password support
- [x] **Ruby 3.2.2 Support** - Modern Ruby version management
- [x] **Comprehensive Error Handling** - Better debugging and troubleshooting
- [ ] Web UI for configuration and monitoring
- [ ] Support for PostgreSQL clusters
- [ ] Machine learning-based anomaly detection
- [ ] Integration with more alerting systems (Teams, Discord)
- [ ] Real-time streaming metrics
- [ ] Mobile app for alerts

---

*Made with ❤️ for the PostgreSQL community*
