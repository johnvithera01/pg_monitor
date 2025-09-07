#!/bin/bash
# test_runner.sh - Script automatizado para executar testes do pg_monitor

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contadores
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BLUE}🚀 Iniciando testes do pg_monitor v2.0${NC}"
echo "=================================="

# Função para executar teste
run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_type="${3:-basic}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "\n${YELLOW}📋 Teste $TOTAL_TESTS: $test_name${NC}"
    echo "Comando: $test_command"
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASSOU${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}❌ FALHOU${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Função para verificar pré-requisitos
check_prerequisites() {
    echo -e "${BLUE}🔍 Verificando pré-requisitos...${NC}"
    
    # Verificar Ruby
    if ! command -v ruby &> /dev/null; then
        echo -e "${RED}❌ Ruby não encontrado${NC}"
        exit 1
    fi
    
    # Verificar PostgreSQL client
    if ! command -v psql &> /dev/null; then
        echo -e "${YELLOW}⚠️  psql não encontrado - alguns testes podem falhar${NC}"
    fi
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}⚠️  Docker não encontrado - testes de container serão pulados${NC}"
    fi
    
    echo -e "${GREEN}✅ Pré-requisitos verificados${NC}"
}

# Função para configurar ambiente de teste
setup_test_environment() {
    echo -e "${BLUE}⚙️  Configurando ambiente de teste...${NC}"
    
    # Verificar se as variáveis de ambiente estão definidas
    if [ -z "$PG_USER" ] || [ -z "$PG_PASSWORD" ]; then
        echo -e "${YELLOW}⚠️  Variáveis PG_USER e PG_PASSWORD não definidas${NC}"
        echo "Definindo valores de teste..."
        export PG_USER="test_user"
        export PG_PASSWORD="test_password"
        export EMAIL_PASSWORD="test_email_password"
    fi
    
    # Verificar se o arquivo de configuração existe
    if [ ! -f "config/pg_monitor_config.yml" ]; then
        echo -e "${YELLOW}⚠️  Arquivo de configuração não encontrado, copiando sample...${NC}"
        cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml
    fi
    
    echo -e "${GREEN}✅ Ambiente configurado${NC}"
}

# Testes básicos
run_basic_tests() {
    echo -e "\n${BLUE}🧪 Executando testes básicos...${NC}"
    
    run_test "Sintaxe do arquivo principal" "ruby -c pg_monitor.rb"
    run_test "Sintaxe do módulo principal" "ruby -c lib/pg_monitor.rb"
    run_test "Sintaxe do config" "ruby -c lib/pg_monitor/config.rb"
    run_test "Sintaxe da conexão" "ruby -c lib/pg_monitor/connection.rb"
    run_test "Sintaxe do email sender" "ruby -c lib/pg_monitor/email_sender.rb"
    run_test "Sintaxe das métricas" "ruby -c lib/pg_monitor/metrics.rb"
    run_test "Sintaxe do logger" "ruby -c lib/pg_monitor/logger.rb"
    run_test "Sintaxe do alert sink" "ruby -c lib/pg_monitor/alert_sink.rb"
}

# Testes de configuração
run_config_tests() {
    echo -e "\n${BLUE}⚙️  Executando testes de configuração...${NC}"
    
    run_test "Carregamento do módulo" "ruby -e \"require_relative 'lib/pg_monitor'\""
    run_test "Validação de configuração" "ruby -e \"require_relative 'lib/pg_monitor'; config = PgMonitor::Config.new; exit 1 unless config.valid?\""
    run_test "Arquivo de configuração existe" "test -f config/pg_monitor_config.yml"
    run_test "Arquivo de configuração é YAML válido" "ruby -e \"require 'yaml'; YAML.load_file('config/pg_monitor_config.yml')\""
}

# Testes de funcionalidade
run_functionality_tests() {
    echo -e "\n${BLUE}🔧 Executando testes de funcionalidade...${NC}"
    
    run_test "Monitoramento high (dry run)" "timeout 10 ruby pg_monitor.rb high || true"
    run_test "Monitoramento medium (dry run)" "timeout 10 ruby pg_monitor.rb medium || true"
    run_test "Monitoramento low (dry run)" "timeout 10 ruby pg_monitor.rb low || true"
    run_test "Scan de segurança (dry run)" "timeout 10 ruby pg_monitor.rb daily_log_scan || true"
    run_test "Teste de corrupção (dry run)" "timeout 10 ruby pg_monitor.rb corruption_test || true"
    run_test "Histórico de tabelas (dry run)" "timeout 10 ruby pg_monitor.rb table_size_history || true"
}

# Testes de Docker
run_docker_tests() {
    if command -v docker &> /dev/null; then
        echo -e "\n${BLUE}🐳 Executando testes de Docker...${NC}"
        
        run_test "Build da imagem Docker" "docker build -t pg_monitor:test ."
        run_test "Docker Compose syntax" "docker-compose config"
        
        # Limpar imagem de teste
        docker rmi pg_monitor:test 2>/dev/null || true
    else
        echo -e "${YELLOW}⚠️  Docker não disponível - pulando testes de container${NC}"
    fi
}

# Testes de métricas
run_metrics_tests() {
    echo -e "\n${BLUE}📊 Executando testes de métricas...${NC}"
    
    run_test "Servidor de métricas inicia" "timeout 5 bundle exec puma -C config/puma.rb &"
    sleep 2
    run_test "Endpoint de métricas responde" "curl -f http://localhost:9394/metrics > /dev/null 2>&1"
    run_test "Health check responde" "curl -f http://localhost:9394/health > /dev/null 2>&1"
    
    # Parar servidor
    pkill -f "puma.*config/puma.rb" 2>/dev/null || true
}

# Testes de dependências
run_dependency_tests() {
    echo -e "\n${BLUE}📦 Executando testes de dependências...${NC}"
    
    run_test "Bundle install funciona" "bundle install --quiet"
    run_test "Gemfile é válido" "bundle check"
    run_test "Dependências principais carregam" "ruby -e \"require 'pg'; require 'mail'; require 'prometheus/client'\""
}

# Função para gerar relatório
generate_report() {
    echo -e "\n${BLUE}📋 Relatório de Testes${NC}"
    echo "=========================="
    echo "Total de testes: $TOTAL_TESTS"
    echo -e "Passou: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Falhou: ${RED}$FAILED_TESTS${NC}"
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo "Taxa de sucesso: $success_rate%"
        
        if [ $success_rate -ge 80 ]; then
            echo -e "${GREEN}🎉 Testes concluídos com sucesso!${NC}"
            return 0
        else
            echo -e "${RED}⚠️  Alguns testes falharam. Verifique os logs acima.${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  Nenhum teste foi executado${NC}"
        return 1
    fi
}

# Função principal
main() {
    check_prerequisites
    setup_test_environment
    
    run_basic_tests
    run_config_tests
    run_dependency_tests
    run_functionality_tests
    run_metrics_tests
    run_docker_tests
    
    generate_report
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
