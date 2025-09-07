#!/bin/bash
# scripts/test_scenarios.sh - Cenários de teste específicos para pg_monitor

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Cenários de Teste - pg_monitor${NC}"
echo "=================================="

# Função para simular cenários
simulate_scenario() {
    local scenario_name="$1"
    local description="$2"
    local setup_command="$3"
    local test_command="$4"
    local cleanup_command="$5"
    
    echo -e "\n${YELLOW}📋 Cenário: $scenario_name${NC}"
    echo "Descrição: $description"
    
    # Setup
    if [ -n "$setup_command" ]; then
        echo "⚙️  Configurando cenário..."
        eval "$setup_command"
    fi
    
    # Executar teste
    echo "🧪 Executando teste..."
    if eval "$test_command"; then
        echo -e "${GREEN}✅ Cenário passou${NC}"
    else
        echo -e "${RED}❌ Cenário falhou${NC}"
    fi
    
    # Cleanup
    if [ -n "$cleanup_command" ]; then
        echo "🧹 Limpando..."
        eval "$cleanup_command"
    fi
}

# Cenário 1: Alta CPU
simulate_scenario \
    "Alta CPU" \
    "Simula alta utilização de CPU para testar alertas" \
    "stress --cpu 2 --timeout 30s &" \
    "ruby pg_monitor.rb high" \
    "pkill -f stress"

# Cenário 2: Muitas Conexões
simulate_scenario \
    "Muitas Conexões" \
    "Cria múltiplas conexões para testar limite" \
    "for i in {1..20}; do psql -c 'SELECT 1;' & done" \
    "ruby pg_monitor.rb high" \
    "pkill -f psql"

# Cenário 3: Transação Longa
simulate_scenario \
    "Transação Longa" \
    "Inicia transação longa para testar detecção" \
    "psql -c 'BEGIN; SELECT pg_sleep(300);' &" \
    "sleep 5; ruby pg_monitor.rb high" \
    "pkill -f 'pg_sleep'"

# Cenário 4: I/O Intenso
simulate_scenario \
    "I/O Intenso" \
    "Simula I/O intenso no disco" \
    "dd if=/dev/zero of=/tmp/testfile bs=1M count=500 &" \
    "ruby pg_monitor.rb high" \
    "pkill -f dd; rm -f /tmp/testfile"

# Cenário 5: Queries Lentas
simulate_scenario \
    "Queries Lentas" \
    "Executa queries que demoram para completar" \
    "psql -c 'SELECT pg_sleep(10);' &" \
    "ruby pg_monitor.rb medium" \
    "pkill -f 'pg_sleep'"

# Cenário 6: Falha de Conexão
simulate_scenario \
    "Falha de Conexão" \
    "Testa comportamento com banco indisponível" \
    "export PG_HOST_OLD=\$PG_HOST; export PG_HOST='nonexistent_host'" \
    "ruby pg_monitor.rb high" \
    "export PG_HOST=\$PG_HOST_OLD"

# Cenário 7: Configuração Inválida
simulate_scenario \
    "Configuração Inválida" \
    "Testa com arquivo de configuração inválido" \
    "mv config/pg_monitor_config.yml config/pg_monitor_config.yml.bak; echo 'invalid: yaml: content' > config/pg_monitor_config.yml" \
    "ruby pg_monitor.rb high" \
    "mv config/pg_monitor_config.yml.bak config/pg_monitor_config.yml"

# Cenário 8: Email Inválido
simulate_scenario \
    "Email Inválido" \
    "Testa com configuração de email inválida" \
    "export EMAIL_PASSWORD_OLD=\$EMAIL_PASSWORD; export EMAIL_PASSWORD='invalid_password'" \
    "ruby pg_monitor.rb high" \
    "export EMAIL_PASSWORD=\$EMAIL_PASSWORD_OLD"

# Cenário 9: Múltiplas Execuções
simulate_scenario \
    "Múltiplas Execuções" \
    "Executa monitoramento múltiplas vezes rapidamente" \
    "" \
    "for i in {1..5}; do ruby pg_monitor.rb high & done; wait" \
    ""

# Cenário 10: Monitoramento Contínuo
simulate_scenario \
    "Monitoramento Contínuo" \
    "Executa monitoramento por período prolongado" \
    "" \
    "timeout 60 bash -c 'while true; do ruby pg_monitor.rb high; sleep 10; done'" \
    ""

echo -e "\n${GREEN}🎉 Todos os cenários de teste foram executados!${NC}"
