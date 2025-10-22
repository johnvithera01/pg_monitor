#!/bin/bash

# scripts/verify_installation.sh
# Script para verificar se a instalação do pg_monitor está funcionando corretamente

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in project directory
if [ ! -f "pg_monitor.rb" ]; then
    log_error "Este script deve ser executado no diretório raiz do pg_monitor"
    exit 1
fi

log_info "🔍 Verificando instalação do pg_monitor..."
echo

# 1. Check Ruby version
log_info "1. Verificando Ruby..."
if command -v ruby &> /dev/null; then
    ruby_version=$(ruby -v | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [[ $(echo "$ruby_version >= 2.7" | bc -l) -eq 1 ]]; then
        log_success "Ruby $ruby_version encontrado"
    else
        log_error "Ruby $ruby_version encontrado. Requer Ruby 2.7+"
        exit 1
    fi
else
    log_error "Ruby não encontrado"
    exit 1
fi

# 2. Check Bundler and gems
log_info "2. Verificando Bundler e gems..."
if command -v bundle &> /dev/null; then
    log_success "Bundler encontrado"

    if bundle check &> /dev/null; then
        log_success "Todas as gems estão instaladas"
    else
        log_warning "Algumas gems podem estar faltando. Execute: bundle install"
    fi
else
    log_error "Bundler não encontrado. Instale com: gem install bundler"
    exit 1
fi

# 3. Check configuration files
log_info "3. Verificando arquivos de configuração..."
if [ -f "config/pg_monitor_config.yml" ]; then
    log_success "Arquivo de configuração encontrado"
else
    log_warning "Arquivo de configuração não encontrado. Copie o template:"
    log_warning "cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml"
fi

if [ -f ".env" ]; then
    log_success "Arquivo .env encontrado"
else
    log_warning "Arquivo .env não encontrado. Copie o template:"
    log_warning "cp .env.example .env"
fi

# 4. Check environment variables
log_info "4. Verificando variáveis de ambiente..."
missing_vars=()
if [ -z "$PG_USER" ]; then
    missing_vars+=("PG_USER")
fi
if [ -z "$PG_PASSWORD" ]; then
    missing_vars+=("PG_PASSWORD")
fi
if [ -z "$EMAIL_PASSWORD" ]; then
    missing_vars+=("EMAIL_PASSWORD")
fi

if [ ${#missing_vars[@]} -eq 0 ]; then
    log_success "Todas as variáveis de ambiente obrigatórias estão configuradas"
else
    log_warning "Variáveis de ambiente faltando: ${missing_vars[*]}"
    log_warning "Configure as variáveis de ambiente ou edite o arquivo .env"
fi

# 5. Check Docker (if applicable)
log_info "5. Verificando Docker..."
if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
    log_success "Docker e Docker Compose encontrados"

    if [ -f "docker-compose.yml" ]; then
        log_success "Arquivo docker-compose.yml encontrado"

        # Check if containers are running
        if docker-compose ps | grep -q "Up"; then
            log_success "Containers Docker estão rodando"
        else
            log_warning "Containers Docker não estão rodando. Execute: docker-compose up -d"
        fi
    fi
else
    log_warning "Docker não encontrado. Instalação tradicional será usada."
fi

# 6. Check PostgreSQL connection (if config exists)
log_info "6. Verificando conexão com PostgreSQL..."
if [ -f "config/pg_monitor_config.yml" ] && [ -n "$PG_USER" ] && [ -n "$PG_PASSWORD" ]; then
    if command -v psql &> /dev/null; then
        # Try to connect (without specifying database to avoid connection issues)
        if psql -h localhost -U "$PG_USER" -c "SELECT version();" &> /dev/null; then
            log_success "Conexão com PostgreSQL estabelecida"
        else
            log_warning "Não foi possível conectar ao PostgreSQL. Verifique configuração."
        fi
    else
        log_warning "Cliente PostgreSQL (psql) não encontrado"
    fi
else
    log_warning "Configuração ou variáveis de ambiente não definidas. Pulando teste de conexão."
fi

# 7. Check syntax
log_info "7. Verificando sintaxe do código..."
if ruby -c pg_monitor.rb &> /dev/null; then
    log_success "Sintaxe do pg_monitor.rb está correta"
else
    log_error "Erro de sintaxe no pg_monitor.rb"
    exit 1
fi

if ruby -c lib/pg_monitor.rb &> /dev/null; then
    log_success "Sintaxe do lib/pg_monitor.rb está correta"
else
    log_error "Erro de sintaxe no lib/pg_monitor.rb"
    exit 1
fi

# 8. Test basic functionality
log_info "8. Testando funcionalidades básicas..."
if [ -f "config/pg_monitor_config.yml" ] && [ -n "$PG_USER" ] && [ -n "$PG_PASSWORD" ]; then
    if timeout 30 ruby pg_monitor.rb high &> /dev/null; then
        log_success "Monitoramento executado com sucesso"
    else
        log_warning "Erro ao executar monitoramento. Verifique logs."
    fi
else
    log_warning "Configuração não completa. Pulando teste de monitoramento."
fi

# 9. Check metrics endpoint (if Docker is running)
log_info "9. Verificando endpoint de métricas..."
if command -v curl &> /dev/null; then
    if curl -s http://localhost:9394/health &> /dev/null; then
        log_success "Endpoint de métricas está respondendo"
    else
        log_warning "Endpoint de métricas não está respondendo. Inicie os serviços."
    fi
else
    log_warning "curl não encontrado para testar endpoints"
fi

# 10. Check cron jobs (if applicable)
log_info "10. Verificando cron jobs..."
if [ -f "/etc/cron.d/pg_monitor" ]; then
    log_success "Cron jobs configurados em /etc/cron.d/pg_monitor"
elif crontab -l 2>/dev/null | grep -q pg_monitor; then
    log_success "Cron jobs configurados no crontab do usuário"
else
    log_warning "Cron jobs não configurados. Configure com:"
    log_warning "sudo cp crontab /etc/cron.d/pg_monitor"
fi

echo
log_info "📋 Resumo da verificação:"
echo

# Final summary
if [ -f "config/pg_monitor_config.yml" ] && [ -f ".env" ] && [ -n "$PG_USER" ] && [ -n "$PG_PASSWORD" ] && [ -n "$EMAIL_PASSWORD" ]; then
    log_success "✅ Configuração básica completa!"
else
    log_warning "⚠️  Configuração incompleta. Complete os passos em INSTALACAO_SERVIDOR.md"
fi

if command -v docker &> /dev/null && docker-compose ps | grep -q "Up"; then
    log_success "✅ Docker containers rodando!"
else
    log_warning "⚠️  Docker containers não estão rodando. Execute: docker-compose up -d"
fi

if ruby -c pg_monitor.rb &> /dev/null && ruby -c lib/pg_monitor.rb &> /dev/null; then
    log_success "✅ Sintaxe do código verificada!"
else
    log_error "❌ Erro de sintaxe no código!"
fi

echo
log_info "🎯 Próximos passos recomendados:"
echo "1. Complete a configuração em .env e config/pg_monitor_config.yml"
echo "2. Execute: docker-compose up -d (se usar Docker)"
echo "3. Teste: curl http://localhost:9394/metrics"
echo "4. Configure cron jobs: sudo cp crontab /etc/cron.d/pg_monitor"
echo "5. Importe dashboards no Grafana: http://localhost:3000"
echo
log_success "Verificação concluída! Consulte INSTALACAO_SERVIDOR.md para instruções detalhadas."
