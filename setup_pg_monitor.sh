#!/bin/bash

# pg_monitor v2.0 - Setup Script
# Instala e configura o pg_monitor em uma nova instância

set -e

# --- Variáveis de Configuração ---
PG_MONITOR_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${PG_MONITOR_BASE_DIR}/config"
LOG_DIR="/var/log/pg_monitor"
PG_MONITOR_CONFIG_FILE="${CONFIG_DIR}/pg_monitor_config.yml"
PG_MONITOR_RB_PATH="${PG_MONITOR_BASE_DIR}/pg_monitor.rb"
ENV_FILE="${PG_MONITOR_BASE_DIR}/.env"

echo "🚀 pg_monitor v2.0 - Setup"
echo "================================"
echo "Diretório: ${PG_MONITOR_BASE_DIR}"
echo ""

# --- 1. Verificar e instalar dependências do sistema ---
echo -e "\n1. Verificando e instalando dependências do sistema..."

# Função para verificar se um comando existe
command_exists () {
  command -v "$1" >/dev/null 2>&1
}

# Distro detection
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
elif [ -f /etc/redhat-release ]; then
    DISTRO="redhat"
else
    DISTRO="unknown"
fi

install_package() {
    PACKAGE_NAME=$1
    COMMAND_NAME=$2 # Comando para verificar se o pacote já está instalado
    if ! command_exists "$COMMAND_NAME"; then
        echo "Instalando ${PACKAGE_NAME}..."
        if [ "$DISTRO" == "debian" ]; then
            sudo apt-get update && sudo apt-get install -y "$PACKAGE_NAME"
        elif [ "$DISTRO" == "redhat" ]; then
            sudo yum install -y "$PACKAGE_NAME" || sudo dnf install -y "$PACKAGE_NAME"
        else
            echo "Distribuição Linux não suportada. Por favor, instale ${PACKAGE_NAME} manualmente."
            exit 1
        fi
        if [ $? -ne 0 ]; then
            echo "Falha ao instalar ${PACKAGE_NAME}. Por favor, instale manualmente e execute o script novamente."
            exit 1
        fi
    else
        echo "${PACKAGE_NAME} já está instalado."
    fi
}

install_package "ruby" "ruby"
install_package "bundler" "bundle" # Bundler é uma gem, mas é bom tê-lo pré-instalado para evitar problemas
install_package "sysstat" "mpstat" # Para mpstat e iostat
# install_package "postgresql-client" "psql" # REMOVIDO: PostgreSQL deve estar instalado externamente
# install_package "postgresql-contrib" "pg_amcheck" # REMOVIDO: PostgreSQL deve estar instalado externamente

echo "Dependências do sistema verificadas/instaladas."
echo "NOTA: Este script assume que PostgreSQL já está instalado no sistema."
echo "      Se PostgreSQL não estiver instalado, instale-o manualmente antes de continuar."

# --- 2. Instalar Ruby Gems ---
echo -e "\n📦 2. Instalando Ruby Gems..."
cd "$PG_MONITOR_BASE_DIR" || { echo "❌ Erro: Não foi possível entrar no diretório base."; exit 1; }

if [ ! -f "Gemfile" ]; then
    echo "❌ Erro: Gemfile não encontrado!"
    echo "   Clone o projeto do GitHub: git clone https://github.com/johnvithera01/pg_monitor.git"
    exit 1
fi

bundle install
if [ $? -ne 0 ]; then
    echo "❌ Falha ao instalar gems. Verifique Ruby/Bundler."
    exit 1
fi
echo "✅ Gems instaladas com sucesso"

# --- 3. Criar estrutura de diretórios ---
echo -e "\n📁 3. Criando diretórios..."
mkdir -p "$CONFIG_DIR"
sudo mkdir -p "$LOG_DIR"
sudo chown $USER:$USER "$LOG_DIR"
echo "✅ Diretórios criados"

# --- 4. Configurar arquivo .env ---
echo -e "\n⚙️  4. Configurando arquivo .env..."
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "${PG_MONITOR_BASE_DIR}/.env.example" ]; then
        cp "${PG_MONITOR_BASE_DIR}/.env.example" "$ENV_FILE"
        echo "✅ Arquivo .env criado a partir do .env.example"
        echo ""
        echo "⚠️  IMPORTANTE: Edite o arquivo .env e configure:"
        echo "   - PG_USER (usuário do PostgreSQL)"
        echo "   - PG_PASSWORD (senha do PostgreSQL)"
        echo "   - EMAIL_PASSWORD (App Password do Gmail)"
        echo ""
        echo "   Execute: nano $ENV_FILE"
    else
        echo "❌ Erro: .env.example não encontrado"
        exit 1
    fi
else
    echo "✅ Arquivo .env já existe"
fi

# --- 5. Verificar arquivo de configuração ---
echo -e "\n⚙️  5. Verificando configuração..."
if [ ! -f "$PG_MONITOR_CONFIG_FILE" ]; then
    echo "❌ Erro: ${PG_MONITOR_CONFIG_FILE} não encontrado"
    echo "   O arquivo de configuração deve estar em: config/pg_monitor_config.yml"
    exit 1
else
    echo "✅ Arquivo de configuração encontrado"
fi

# --- 6. Testar Instalação ---
echo -e "\n🧪 6. Testando instalação..."
if ruby -c "$PG_MONITOR_RB_PATH" > /dev/null 2>&1; then
    echo "✅ Sintaxe do pg_monitor.rb OK"
else
    echo "❌ Erro de sintaxe no pg_monitor.rb"
    exit 1
fi

# --- 7. Instruções Finais ---
echo ""
echo "================================"
echo "✅ Setup Concluído!"
echo "================================"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo ""
echo "1️⃣  Editar arquivo .env:"
echo "   nano $ENV_FILE"
echo "   Configure: PG_USER, PG_PASSWORD, EMAIL_PASSWORD"
echo ""
echo "2️⃣  Editar configuração:"
echo "   nano $PG_MONITOR_CONFIG_FILE"
echo "   Configure: host, port, emails"
echo ""
echo "3️⃣  Testar execução:"
echo "   ruby $PG_MONITOR_RB_PATH high"
echo ""
echo "4️⃣  Configurar cron jobs:"
echo "   crontab -e"
echo ""
echo "   # Monitoramento crítico (a cada 2 minutos)"
echo "   */2 * * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb high >> ${LOG_DIR}/cron.log 2>&1"
echo ""
echo "   # Performance (a cada 30 minutos)"
echo "   */30 * * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb medium >> ${LOG_DIR}/cron.log 2>&1"
echo ""
echo "   # Manutenção (a cada 6 horas)"
echo "   0 */6 * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb low >> ${LOG_DIR}/cron.log 2>&1"
echo ""
echo "📚 Documentação:"
echo "   - README.md"
echo "   - DOCKER_INSTALL.md"
echo "   - README_INSTALACAO.md"
echo ""
echo "🎉 pg_monitor v2.0 pronto para usar!"