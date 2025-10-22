# 📖 Guia de Instalação - pg_monitor v2.0

## ⚠️ Pré-requisito IMPORTANTE

**Este projeto assume que você JÁ TEM PostgreSQL instalado e rodando no seu servidor.**

O `pg_monitor` é uma ferramenta de **monitoramento** que se conecta a um PostgreSQL existente. Ele **NÃO instala** o PostgreSQL.

---

## 🚀 Instalação Rápida

### Opção 1: Script Automatizado (Recomendado)

```bash
# 1. Clone o repositório
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor

# 2. Execute o script de instalação
chmod +x setup_pg_monitor.sh
./setup_pg_monitor.sh

# 3. Configure suas credenciais
nano config/pg_monitor_config.yml

# 4. Configure variáveis de ambiente
export PG_USER="seu_usuario_postgres"
export PG_PASSWORD="sua_senha_postgres"
export EMAIL_PASSWORD="sua_senha_email"

# 5. Teste a conexão
ruby pg_monitor.rb high
```

### Opção 2: Docker (Para ambientes containerizados)

```bash
# 1. Clone o repositório
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor

# 2. Configure variáveis de ambiente
cp .env.example .env
nano .env  # Edite com suas credenciais

# 3. Configure o host do PostgreSQL
nano config/pg_monitor_config.yml
# Altere o 'host' para o IP/hostname do seu PostgreSQL

# 4. Inicie os serviços (pg_monitor, Prometheus, Grafana)
docker-compose up -d

# 5. Verifique os logs
docker-compose logs -f pg_monitor
```

---

## 📋 O que é instalado

### Script `setup_pg_monitor.sh` instala:
- ✅ Ruby (linguagem de programação)
- ✅ Bundler (gerenciador de gems)
- ✅ sysstat (para monitoramento de CPU/IO)
- ✅ Gems Ruby necessárias (pg, mail, etc.)
- ✅ Estrutura de diretórios e configuração

### Docker Compose instala:
- ✅ pg_monitor (aplicação de monitoramento)
- ✅ Prometheus (coleta de métricas)
- ✅ Grafana (visualização de dashboards)
- ❌ **NÃO instala PostgreSQL** (deve estar instalado externamente)

---

## 🔧 Configuração do PostgreSQL Existente

### 1. Criar usuário para monitoramento

Conecte-se ao seu PostgreSQL e execute:

```sql
-- Criar usuário de monitoramento
CREATE USER pgmonitor WITH PASSWORD 'senha_segura_aqui';

-- Conceder permissões necessárias
GRANT CONNECT ON DATABASE seu_banco TO pgmonitor;
GRANT USAGE ON SCHEMA public TO pgmonitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pgmonitor;

-- Para PostgreSQL 10+, conceder role de monitoramento
GRANT pg_monitor TO pgmonitor;

-- Permissões adicionais para funcionalidades avançadas
GRANT SELECT ON pg_stat_activity TO pgmonitor;
GRANT SELECT ON pg_stat_database TO pgmonitor;
GRANT SELECT ON pg_stat_user_tables TO pgmonitor;
```

### 2. Configurar pg_monitor_config.yml

```yaml
database:
  host: "192.168.1.100"  # IP do seu servidor PostgreSQL
  port: 5432
  name: "seu_banco"      # Nome do banco a monitorar
  # user e password vêm das variáveis de ambiente

email:
  sender_email: "monitor@suaempresa.com"
  receiver_email: "dba@suaempresa.com"
  smtp_address: "smtp.gmail.com"
  smtp_port: 587
  smtp_domain: "gmail.com"

thresholds:
  cpu_threshold_percent: 80
  heap_cache_hit_ratio_min: 95
  query_alert_threshold_minutes: 5
  alert_cooldown_minutes: 60
```

### 3. Configurar variáveis de ambiente

```bash
# Método 1: Exportar no shell
export PG_USER="pgmonitor"
export PG_PASSWORD="senha_segura_aqui"
export EMAIL_PASSWORD="senha_app_email"

# Método 2: Arquivo .env (para Docker)
cat > .env << EOF
PG_USER=pgmonitor
PG_PASSWORD=senha_segura_aqui
EMAIL_PASSWORD=senha_app_email
GRAFANA_PASSWORD=admin
EOF
```

---

## 🧪 Testar Instalação

### Teste de Conexão

```bash
# Teste manual de conexão
psql -h 192.168.1.100 -U pgmonitor -d seu_banco -c "SELECT version();"

# Teste via pg_monitor
ruby pg_monitor.rb high

# Verificar logs
tail -f /var/log/pg_monitor/pg_monitor.log
```

### Teste com Docker

```bash
# Verificar status dos containers
docker-compose ps

# Verificar logs
docker-compose logs pg_monitor

# Testar métricas
curl http://localhost:9394/metrics

# Acessar Grafana
# http://localhost:3000 (admin/admin)
```

---

## 📊 Configurar Monitoramento Contínuo

### Cron Jobs (Instalação Tradicional)

```bash
# Editar crontab
crontab -e

# Adicionar jobs de monitoramento
*/2 * * * * cd /opt/pg_monitor && /usr/bin/ruby pg_monitor.rb high >> /var/log/pg_monitor/cron.log 2>&1
*/30 * * * * cd /opt/pg_monitor && /usr/bin/ruby pg_monitor.rb medium >> /var/log/pg_monitor/cron.log 2>&1
0 */6 * * * cd /opt/pg_monitor && /usr/bin/ruby pg_monitor.rb low >> /var/log/pg_monitor/cron.log 2>&1
```

### Docker (Scheduler Automático)

O container `pg_monitor_scheduler` já executa os jobs automaticamente via cron.

---

## 🔍 Troubleshooting

### Erro: "Connection refused"

```bash
# Verificar se PostgreSQL está rodando
sudo systemctl status postgresql

# Verificar se PostgreSQL aceita conexões remotas
sudo nano /etc/postgresql/*/main/postgresql.conf
# Alterar: listen_addresses = '*'

sudo nano /etc/postgresql/*/main/pg_hba.conf
# Adicionar: host all all 0.0.0.0/0 md5

sudo systemctl restart postgresql
```

### Erro: "Authentication failed"

```bash
# Verificar credenciais
psql -h localhost -U pgmonitor -d postgres

# Verificar variáveis de ambiente
echo $PG_USER
echo $PG_PASSWORD

# Recriar usuário se necessário
sudo -u postgres psql -c "DROP USER IF EXISTS pgmonitor;"
sudo -u postgres psql -c "CREATE USER pgmonitor WITH PASSWORD 'nova_senha';"
```

### Erro: "Permission denied"

```bash
# Conceder permissões novamente
sudo -u postgres psql -d seu_banco << EOF
GRANT pg_monitor TO pgmonitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pgmonitor;
EOF
```

---

## 📞 Suporte

- **Documentação**: [README.md](README.md)
- **Issues**: https://github.com/johnvithera01/pg_monitor/issues
- **Logs**: `/var/log/pg_monitor/pg_monitor.log`

---

## ✅ Checklist de Instalação

- [ ] PostgreSQL instalado e rodando
- [ ] Usuário `pgmonitor` criado no PostgreSQL
- [ ] Permissões concedidas ao usuário
- [ ] Ruby 2.7+ instalado
- [ ] Gems instaladas (`bundle install`)
- [ ] Arquivo `config/pg_monitor_config.yml` configurado
- [ ] Variáveis de ambiente configuradas
- [ ] Teste de conexão bem-sucedido
- [ ] Cron jobs configurados (ou Docker rodando)
- [ ] Grafana acessível (se usando Docker)

**🎉 Instalação completa! Seu PostgreSQL está sendo monitorado!**
