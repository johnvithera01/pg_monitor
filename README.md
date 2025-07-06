# pg_monitor.rb

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## 🚀 Overview

`pg_monitor.rb` is a robust and intelligent Ruby script designed for **proactive PostgreSQL monitoring and advanced security**. It automates the detection of performance, security, and integrity issues, sending detailed, contextualized alerts via email, transforming reactive database management into a proactive strategy.

## 🤔 Why This Script? The Pains It Solves

As DBAs and SysAdmins, we've all been there:
* **Unexpected performance spikes:** CPU and I/O soaring, with no immediate clue as to the cause.
* **Stuck transactions and locks:** Bottlenecks that paralyze applications and demand urgent manual intervention.
* **Silent security threats:** Failed login attempts buried in logs, difficult to track manually.
* **Data corruption:** Every DBA's nightmare, with the integrity of your most valuable asset constantly at risk.
* **Unexplained slowness:** Doubts about inefficient indexes, misconfigured `autovacuum`, or unoptimized queries.
* **Sleepless nights:** Constant worry and alerts that arrive too late.

`pg_monitor.rb` was created to alleviate these pains by providing essential visibility, automation, and peace of mind.

## ✨ Key Features

This script offers multiple monitoring levels and advanced capabilities:

* **Intelligent & Contextual Alerts (Level `high`):**
    * Monitors CPU and I/O, correlating with active processes and problematic queries.
    * Detects and alerts on excessive connections and `idle in transaction` sessions.
    * Monitors `Cache Hit Ratio` for insights into memory efficiency.
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
    * Ability to identify and **automatically terminate** processes that exceed predefined limits (e.g., long-running transactions), preventing database crashes.
* **Table Size History (Level `table_size_history`):**
    * Saves a historical record of table sizes to track growth and plan optimizations.

## ⚙️ Prerequisites

To use `pg_monitor.rb`, you will need:

* **Ruby:** Version 2.5 or higher.
* **Ruby Gems:** `pg`, `json`, `time`, `mail`, `fileutils`. Install them via Bundler or manually:
    ```bash
    gem install pg json mail fileutils
    ```
* **PostgreSQL Database Access:** A user with read permissions (and write permissions for `pg_monitor.failed_logins` and `pg_monitor.table_size_history` tables).
* **Operating System Access:** For `mpstat` (for CPU) and `iostat` (for I/O), which typically come with the `sysstat` package (install if necessary: `sudo apt-get install sysstat` on Debian/Ubuntu).
* **`pg_amcheck`:** Tool for corruption verification (usually part of `postgresql-contrib` or installed separately).
* **SMTP Server:** For sending emails (Gmail is configured by default).

## 🚀 Installation & Configuration

### 1. Clone the Repository

```bash
git clone [https://github.com/YourUsername/pg_monitor.rb.git](https://github.com/YourUsername/pg_monitor.rb.git) # Change 'YourUsername' to your actual GitHub username
cd pg_monitor.rb

# --- Database Configuration ---
PG_HOST=your_postgresql_host # E.g., localhost or server IP
PG_PORT=5432
PG_DATABASE=your_database_name
PG_USER=your_db_user
PG_PASSWORD=your_db_password

# --- Email Configuration ---
SENDER_EMAIL=your_sending_email@gmail.com
EMAIL_PASSWORD=your_app_password_or_regular_password # For Gmail, use an App Password
RECEIVER_EMAIL=destination_email_for_alerts@example.com
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587 # Standard port for TLS/STARTTLS
SMTP_DOMAIN=gmail.com

# --- Thresholds and Logs Configuration (Adjust as needed) ---
CPU_ALERT_THRESHOLD=80                      # CPU threshold (%)
IO_ALERT_THRESHOLD=80                       # I/O utilization threshold (%)
CONNECTIONS_ALERT_THRESHOLD=90              # Connections threshold (%)
IDLE_IN_TX_THRESHOLD_SECONDS=300            # Max time in seconds for idle in transaction queries
TX_WRAPAROUND_THRESHOLD_MILLIONS=100        # Max transaction age in millions before alerting
CACHE_HIT_RATIO_THRESHOLD_PERCENT=90        # Cache Hit Ratio percentage below which an alert will be generated
MAX_PROCESS_DURATION_SECONDS=3600           # Max duration (in seconds) a process can run before being considered for auto-kill (if enabled)
AUTO_KILL_ROGUE_PROCESSES=false             # true/false - Enable/disable automatic killing of rogue processes
PG_LOG_PATH=/var/log/postgresql             # Full path to the PostgreSQL log directory
PG_LOG_FILE_PATTERN='postgresql-*.log'      # Log file name pattern (e.g., 'postgresql-*.log' for rotated logs)
3. PostgreSQL Configuration (postgresql.conf)
For efficient security monitoring and logging, ensure your postgresql.conf has the following settings (restart PostgreSQL after making changes):

Ini, TOML

log_line_prefix = '%m %u %d %h %p %r %l %v %c %x %t ' # Essential for capturing necessary information in logs
log_connections = on
log_disconnections = on
log_duration = on
log_lock_waits = on
log_temp_files = 0 # or a value you prefer
log_checkpoints = on
log_autovacuum_min_duration = 0 # To log all autovacuums and identify inefficiencies
🏃 How to Use
The script can be executed at different frequency levels, depending on the type of monitoring you require.

Basic Syntax:

Bash

ruby pg_monitor.rb [frequency_level]
Available Frequency Levels:

high: High-frequency monitoring (CPU, I/O, Connections, Long Transactions, Cache Hit Ratio, Transaction ID Wraparound). Ideal for execution every 1-5 minutes.

medium: Medium-frequency monitoring (Inefficient Autovacuum, Unused/Redundant Indexes). Ideal for hourly execution.

low: Low-frequency monitoring (Top 10 Slow Queries, Disk Usage). Ideal for daily execution.

corruption_test: Tests data and index integrity using pg_amcheck. Ideal for weekly execution.

daily_log_scan: Scans PostgreSQL logs for failed login attempts and records them. Ideal for daily execution (after log rotation).

weekly_login_summary: Generates and sends an email with a weekly summary of failed login attempts. Ideal for weekly execution.

table_size_history: Saves table size history for growth tracking and planning. Ideal for daily execution.

Usage Examples:

Bash

# Execute high-frequency monitoring
ruby pg_monitor.rb high

# Scan security logs daily
ruby pg_monitor.rb daily_log_scan

# Run a corruption test
ruby pg_monitor.rb corruption_test
Example cron Configuration
To automate execution, add the lines to your crontab (type crontab -e in the terminal). Ensure the path to the script is correct and that environment variables are loaded if you are using them via a .env file or directly.

Code snippet

# CRONTAB Example
# Change '*/5' for desired frequency (every 5 minutes)
# Change '/path/to/your/pg_monitor.rb' to the actual script path

# High-Frequency Monitoring (every 5 minutes)
*/5 * * * * cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb high >> /var/log/pg_monitor_high.log 2>&1

# Medium-Frequency Monitoring (every hour)
0 * * * * cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb medium >> /var/log/pg_monitor_medium.log 2>&1

# Low-Frequency / Daily Analysis (once daily, at 2 AM)
0 2 * * * cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb low >> /var/log/pg_monitor_low.log 2>&1

# Daily Security Log Scan (once daily, at 3 AM)
0 3 * * * cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb daily_log_scan >> /var/log/pg_monitor_log_scan.log 2>&1

# Table Size History (once daily, at 3:30 AM)
30 3 * * * cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb table_size_history >> /var/log/pg_monitor_table_size.log 2>&1

# Corruption Test (weekly, every Sunday at 4 AM)
0 4 * * 0 cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb corruption_test >> /var/log/pg_monitor_corruption.log 2>&1

# Weekly Failed Logins Summary (weekly, every Sunday at 4:30 AM)
30 4 * * 0 cd /path/to/your/pg_monitor.rb && /usr/bin/ruby pg_monitor.rb weekly_login_summary >> /var/log/pg_monitor_weekly_summary.log 2>&1
Important: Adjust /path/to/your/pg_monitor.rb to the actual directory where your script is located. Ensure the cron user has the necessary permissions and that environment variables (if used) are loaded within the cron environment.

🚨 Important Notes
Email Alerts: When an alert is detected (e.g., CPU threshold exceeded), an email will be sent to the RECEIVER_EMAIL.

Local Time in Alerts: All timestamps in email alerts will reflect the local time of the server executing the script (e.g., "Monitoramento HIGH em 06/07/2025 13:57:05 (Goiânia, GO, Brasil) detectou os seguintes problemas/informações:").

🤝 Contributing
Contributions are highly welcome! If you have ideas for improvements, new features, or find any bugs, feel free to:

Fork the repository.

Create a new branch (git checkout -b feature/your-feature).

Make your changes and commit them (git commit -m 'Adds new feature').

Push to your branch (git push origin feature/your-feature).

Open a Pull Request.

📄 License
This project is licensed under the Apache License 2.0. See the LICENSE file for more details.
