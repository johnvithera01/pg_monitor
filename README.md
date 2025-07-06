# pg_monitor

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## 🚀 Overview

`pg_monitor` is a robust and intelligent Ruby script designed for **proactive PostgreSQL monitoring and advanced security**. It automates the detection of performance, security, and integrity issues, sending detailed, contextualized alerts via email, transforming reactive database management into a proactive strategy.

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

## 🚀 Installation & Configuration

### 1. Clone the Repository

```bash
git clone [https://github.com/YourUsername/pg_monitor.git](https://github.com/YourUsername/pg_monitor.git) # Change 'YourUsername' to your actual GitHub username
cd pg_monitor
