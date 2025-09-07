# 📋 Plano de Teste - pg_monitor v2.0

## 🎯 Objetivo
Validar todas as funcionalidades do pg_monitor em diferentes cenários e ambientes.

## 📊 Estrutura dos Testes

### 1. **Testes de Configuração e Setup**

#### 1.1 Teste de Instalação
```bash
# Teste 1: Instalação via Docker
make docker-build
make docker-run
docker-compose ps

# Teste 2: Instalação nativa
bundle install
make setup
```

#### 1.2 Teste de Configuração
```bash
# Teste 3: Validação de configuração
ruby -e "require_relative 'lib/pg_monitor'; config = PgMonitor::Config.new; puts config.valid? ? 'OK' : config.validation_errors"

# Teste 4: Variáveis de ambiente
export PG_USER="test_user"
export PG_PASSWORD="test_password"
export EMAIL_PASSWORD="test_email_password"
ruby -e "require_relative 'lib/pg_monitor'; config = PgMonitor::Config.new; puts 'Environment OK'"
```

#### 1.3 Teste de Conexão
```bash
# Teste 5: Conexão com banco
make db-test-connection

# Teste 6: Conexão via script principal
ruby pg_monitor.rb high
```

### 2. **Testes de Monitoramento**

#### 2.1 Monitoramento de Alta Frequência (high)
```bash
# Teste 7: CPU Monitoring
# Simular alta CPU
stress --cpu 4 --timeout 30s &
ruby pg_monitor.rb high

# Teste 8: Conexões
# Criar muitas conexões
for i in {1..50}; do psql -c "SELECT 1;" & done
ruby pg_monitor.rb high

# Teste 9: Transações longas
psql -c "BEGIN; SELECT pg_sleep(300);" &
ruby pg_monitor.rb high

# Teste 10: I/O de disco
dd if=/dev/zero of=/tmp/testfile bs=1M count=1000 &
ruby pg_monitor.rb high
```

#### 2.2 Monitoramento de Média Frequência (medium)
```bash
# Teste 11: Autovacuum
ruby pg_monitor.rb medium

# Teste 12: Queries lentas
psql -c "SELECT pg_sleep(10);" &
ruby pg_monitor.rb medium
```

#### 2.3 Monitoramento de Baixa Frequência (low)
```bash
# Teste 13: Análise de índices
ruby pg_monitor.rb low

# Teste 14: Espaço em disco
ruby pg_monitor.rb low
```

### 3. **Testes de Segurança**

#### 3.1 Logs de Segurança
```bash
# Teste 15: Scan de logs
ruby pg_monitor.rb daily_log_scan

# Teste 16: Resumo semanal
ruby pg_monitor.rb weekly_login_summary
```

#### 3.2 Teste de Corrupção
```bash
# Teste 17: Verificação de integridade
ruby pg_monitor.rb corruption_test
```

### 4. **Testes de Alertas**

#### 4.1 Alertas por Email
```bash
# Teste 18: Configurar email de teste
export EMAIL_PASSWORD="your_app_password"
ruby pg_monitor.rb high

# Teste 19: Cooldown de alertas
ruby pg_monitor.rb high
ruby pg_monitor.rb high  # Deve ser suprimido
```

#### 4.2 Alertas Slack
```bash
# Teste 20: Slack webhook
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
ruby pg_monitor.rb high
```

#### 4.3 Webhooks Customizados
```bash
# Teste 21: Webhook customizado
export WEBHOOK_URL="https://httpbin.org/post"
ruby pg_monitor.rb high
```

### 5. **Testes de Métricas Prometheus**

#### 5.1 Exposição de Métricas
```bash
# Teste 22: Servidor de métricas
bundle exec puma -C config/puma.rb &
curl http://localhost:9394/metrics

# Teste 23: Health check
curl http://localhost:9394/health
```

#### 5.2 Integração Prometheus
```bash
# Teste 24: Scraping
docker-compose up -d prometheus
curl http://localhost:9090/targets
```

### 6. **Testes de Docker**

#### 6.1 Container Principal
```bash
# Teste 25: Build e run
docker build -t pg_monitor:test .
docker run -d --name pg_monitor_test \
  -e PG_USER=test \
  -e PG_PASSWORD=test \
  -e EMAIL_PASSWORD=test \
  pg_monitor:test

# Teste 26: Logs do container
docker logs pg_monitor_test
```

#### 6.2 Docker Compose
```bash
# Teste 27: Stack completo
docker-compose up -d
docker-compose ps
docker-compose logs pg_monitor
```

### 7. **Testes de Performance**

#### 7.1 Carga de Trabalho
```bash
# Teste 28: Múltiplas execuções
for i in {1..10}; do
  ruby pg_monitor.rb high &
done
wait

# Teste 29: Monitoramento contínuo
timeout 300 bash -c 'while true; do ruby pg_monitor.rb high; sleep 30; done'
```

### 8. **Testes de Cenários de Erro**

#### 8.1 Falhas de Conexão
```bash
# Teste 30: Banco indisponível
export PG_HOST="nonexistent_host"
ruby pg_monitor.rb high

# Teste 31: Credenciais inválidas
export PG_PASSWORD="wrong_password"
ruby pg_monitor.rb high
```

#### 8.2 Configuração Inválida
```bash
# Teste 32: Arquivo de config ausente
mv config/pg_monitor_config.yml config/pg_monitor_config.yml.bak
ruby pg_monitor.rb high
mv config/pg_monitor_config.yml.bak config/pg_monitor_config.yml
```

### 9. **Testes de Integração**

#### 9.1 Grafana Dashboard
```bash
# Teste 33: Importar dashboard
docker-compose up -d grafana
# Acessar http://localhost:3000
# Importar dashboards/pg_monitor_overview.json
```

#### 9.2 Cron Jobs
```bash
# Teste 34: Execução via cron
echo "*/1 * * * * cd $(pwd) && ruby pg_monitor.rb high" | crontab -
# Aguardar execução
crontab -l
```

### 10. **Testes de Dados**

#### 10.1 Histórico de Tabelas
```bash
# Teste 35: Salvar histórico
ruby pg_monitor.rb table_size_history

# Teste 36: Verificar dados
psql -c "SELECT * FROM manutencao.size_table_history ORDER BY data_coleta DESC LIMIT 5;"
```

## 🧪 Script de Teste Automatizado

### Criar script de teste
```bash
#!/bin/bash
# test_runner.sh

set -e

echo "🚀 Iniciando testes do pg_monitor..."

# Função para executar teste
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "📋 Executando: $test_name"
    if eval "$test_command"; then
        echo "✅ $test_name - PASSOU"
    else
        echo "❌ $test_name - FALHOU"
        return 1
    fi
}

# Executar testes
run_test "Sintaxe Ruby" "ruby -c pg_monitor.rb"
run_test "Configuração válida" "ruby -e \"require_relative 'lib/pg_monitor'; config = PgMonitor::Config.new; exit 1 unless config.valid?\""
run_test "Conexão DB" "make db-test-connection"
run_test "Monitoramento high" "ruby pg_monitor.rb high"
run_test "Monitoramento medium" "ruby pg_monitor.rb medium"
run_test "Monitoramento low" "ruby pg_monitor.rb low"

echo "🎉 Testes concluídos!"
```

## 📈 Critérios de Sucesso

### ✅ Testes Obrigatórios (Devem passar 100%)
- [ ] Sintaxe Ruby válida
- [ ] Configuração carregada corretamente
- [ ] Conexão com banco estabelecida
- [ ] Métricas expostas via HTTP
- [ ] Alertas enviados por email

### ⚠️ Testes Opcionais (Podem falhar em ambiente de teste)
- [ ] Slack webhooks (requer configuração)
- [ ] Webhooks customizados (requer endpoint)
- [ ] Grafana dashboard (requer setup)
- [ ] Cron jobs (requer permissões)

## 🔧 Ambiente de Teste Recomendado

### Pré-requisitos
```bash
# Instalar dependências de teste
sudo apt-get install -y postgresql-client sysstat stress-ng

# Configurar PostgreSQL de teste
sudo -u postgres createdb test_monitor
sudo -u postgres psql -c "CREATE USER test_user WITH PASSWORD 'test_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE test_monitor TO test_user;"
```

### Variáveis de Ambiente de Teste
```bash
export PG_USER="test_user"
export PG_PASSWORD="test_password"
export PG_HOST="localhost"
export PG_DB="test_monitor"
export EMAIL_PASSWORD="test_email_password"
```

## 📝 Relatório de Testes

### Template de Relatório
```markdown
# Relatório de Testes - pg_monitor v2.0
**Data:** $(date)
**Ambiente:** $(uname -a)
**Versão Ruby:** $(ruby -v)

## Resumo
- Total de testes: XX
- Passou: XX
- Falhou: XX
- Taxa de sucesso: XX%

## Detalhes dos Testes
| Teste | Status | Observações |
|-------|--------|-------------|
| 1. Sintaxe | ✅ | - |
| 2. Configuração | ✅ | - |
| ... | ... | ... |

## Problemas Encontrados
- Nenhum problema crítico encontrado
- Melhorias sugeridas: [lista]

## Conclusão
O pg_monitor está funcionando corretamente e pronto para uso em produção.
```

## 🚀 Execução dos Testes

### Teste Rápido (5 minutos)
```bash
chmod +x test_runner.sh
./test_runner.sh
```

### Teste Completo (30 minutos)
```bash
# Executar todos os testes sequencialmente
for test in {1..36}; do
    echo "Executando teste $test..."
    # Executar comando do teste
done
```

### Teste de Carga (1 hora)
```bash
# Executar monitoramento contínuo
timeout 3600 bash -c 'while true; do ruby pg_monitor.rb high; sleep 60; done'
```

---

**Nota:** Este plano de teste deve ser executado em um ambiente controlado antes de usar em produção. Sempre faça backup dos dados antes de executar testes que possam afetar o banco de dados.
