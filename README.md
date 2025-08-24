# pg_monitor

Lightweight **PostgreSQL monitoring** tool written in Ruby, with support for **Prometheus metrics** and ready-to-use **Grafana dashboards**.  
This project focuses on detecting common PostgreSQL issues and making observability simple.

---

## 🚀 Features

- Collects critical PostgreSQL metrics:
  - Idle in transaction sessions
  - Slow queries
  - Transaction ID age (wraparound prevention)
  - Abnormal table growth
  - Failed login attempts
- Exposes metrics on `/metrics` endpoint (Prometheus format)
- Ready-to-import Grafana dashboard (`dashboards/pg_monitor_overview.json`)
- Easy configuration via YAML or environment variables
- Prepared for external integrations (e.g., Protheus ERP)

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
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
bundle install
```

---

## ▶️ Usage

### Start the Exporter
Run Rackup to expose the `/metrics` endpoint:
```bash
bundle exec rackup -p 9394 -o 0.0.0.0
```

Test it:
```bash
curl http://localhost:9394/metrics
```

You should see metrics being returned.

---

## 📊 Prometheus Integration

Update your `prometheus.yml` configuration:

```yaml
scrape_configs:
  - job_name: 'pg_monitor'
    static_configs:
      - targets: ['localhost:9394']
```

Start Prometheus:
```bash
prometheus --config.file=prometheus.yml
```

Now Prometheus will scrape data from `pg_monitor`.

---

## 📈 Grafana Integration

1. **Install Grafana**  
   - macOS:  
     ```bash
     brew install grafana
     brew services start grafana
     ```  
   - Open: [http://localhost:3000](http://localhost:3000)  
     (default user/password: `admin` / `admin`)

2. **Add Prometheus as a Data Source**  
   - In Grafana: **Connections → Data Sources → Add data source → Prometheus**  
   - URL: `http://localhost:9090` (adjust if your Prometheus runs elsewhere)  
   - Click **Save & Test**

3. **Import the Dashboard**  
   - In Grafana: **+ (Create) → Import**  
   - Click **Upload JSON file**  
   - Select `dashboards/pg_monitor_overview.json` from this repo  
   - Choose your Prometheus data source  
   - Click **Import**

🎉 Done! You’ll now see `pg_monitor` dashboards in Grafana.

---

## ⚙️ Configuration

You can configure `pg_monitor` via a YAML file or environment variables.

Example `config/pg_monitor.yml`:
```yaml
postgres:
  host: localhost
  port: 5432
  db: postgres
  user: postgres
  pass: postgres

thresholds:
  idle_in_tx_minutes: 5
  slow_query_ms: 2000
  xid_age_warning: 150000000
  xid_age_critical: 190000000
  table_growth_pct_warning: 20
  table_growth_pct_critical: 40
```

---

## 📅 Roadmap

- [x] Expose Prometheus-compatible metrics
- [x] Grafana dashboard
- [ ] Intelligent alerts with severity levels
- [ ] Executive reports (PDF/HTML)
- [ ] Auto-healing (terminate rogue queries, run VACUUM automatically)
- [ ] Security module (login failure detection & analysis)
- [ ] SaaS integration

---

## 🤝 Contributing

Contributions are welcome!  
Feel free to open an issue or submit a pull request with improvements.

---

## 📜 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
