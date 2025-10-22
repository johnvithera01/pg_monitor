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

echo "🚀 pg_monitor v2.0 - Setup Automático COMPLETO"
echo "================================================"
echo "Diretório: ${PG_MONITOR_BASE_DIR}"
echo ""
echo "Este script irá fazer TUDO automaticamente:"
echo "  ✅ Instalar Ruby 3.2.2 (rápido, usando ruby-install)"
echo "  ✅ Instalar todas as gems"
echo "  ✅ Configurar .env e YAML"
echo "  ✅ Testar a instalação"
echo "  ✅ Configurar cron jobs (opcional)"
echo ""
echo "⏱️  Tempo estimado: 2-5 minutos"
echo ""

# Função para ler input com valor padrão
read_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " input
    eval $var_name="${input:-$default}"
}

# --- 0. Coletar Informações de Configuração ---
echo "📝 Configuração Inicial"
echo "========================"
echo ""
echo "Vamos configurar o pg_monitor. Pressione ENTER para usar o valor padrão."
echo ""

read_with_default "🔹 Host do PostgreSQL" "127.0.0.1" PG_HOST
read_with_default "🔹 Porta do PostgreSQL" "5432" PG_PORT
read_with_default "🔹 Nome do banco de dados" "postgres" PG_DBNAME
read_with_default "🔹 Usuário do PostgreSQL" "postgres" PG_USER
read -sp "🔹 Senha do PostgreSQL: " PG_PASSWORD
echo ""
read_with_default "🔹 Email remetente (Gmail)" "monitor.postgresql@gmail.com" SENDER_EMAIL
read_with_default "🔹 Email destinatário" "admin@example.com" RECEIVER_EMAIL
read -sp "🔹 Senha App do Gmail: " EMAIL_PASSWORD
echo ""
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

# Instalar dependências básicas (precisa sudo apenas aqui)
echo "📦 Instalando dependências do sistema..."
if [ "$DISTRO" == "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y git curl autoconf bison build-essential libssl-dev \
        libyaml-dev libreadline6-dev zlib1g-dev libgmp-dev libncurses5-dev \
        libffi-dev libgdbm-dev libdb-dev uuid-dev libreadline-dev sysstat
elif [ "$DISTRO" == "redhat" ]; then
    sudo yum install -y git curl gcc make openssl-devel readline-devel \
        zlib-devel libyaml-devel libffi-devel gdbm-devel ncurses-devel \
        autoconf bison gmp-devel libdb-devel libuuid-devel sysstat
fi
echo "✅ Dependências do sistema instaladas"

# Instalar rbenv e ruby-build
if ! command_exists "rbenv"; then
    echo "📦 Instalando rbenv..."
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv
    
    # Compilar rbenv para melhor performance
    cd ~/.rbenv && src/configure && make -C src
    
    # Adicionar ao PATH
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
    
    # Carregar rbenv na sessão atual
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init - bash)"
    
    # Instalar ruby-build
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
    
    echo "✅ rbenv instalado"
else
    echo "✅ rbenv já está instalado"
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init - bash)"
fi

# Instalar Ruby via rbenv
RUBY_VERSION="3.2.2"
if ! rbenv versions 2>/dev/null | grep -q "$RUBY_VERSION"; then
    echo "📦 Instalando Ruby $RUBY_VERSION via rbenv..."
    echo "⏱️  Isso pode demorar 2-5 minutos..."
    
    # Configurar para compilação mais rápida
    export RUBY_CONFIGURE_OPTS="--disable-install-doc --disable-install-rdoc"
    export MAKE_OPTS="-j$(nproc)"
    
    # Instalar Ruby (forçando uso de todos os cores)
    MAKE_OPTS="-j$(nproc)" rbenv install $RUBY_VERSION
    rbenv global $RUBY_VERSION
    rbenv rehash
    
    echo "✅ Ruby $RUBY_VERSION instalado"
else
    echo "✅ Ruby $RUBY_VERSION já está instalado"
    rbenv global $RUBY_VERSION
    rbenv rehash
fi

# Garantir que estamos usando o Ruby correto
eval "$(rbenv init - bash)"

# Instalar bundler
if ! command_exists "bundle"; then
    echo "📦 Instalando bundler..."
    gem install bundler --no-document
    rbenv rehash
    echo "✅ Bundler instalado"
else
    echo "✅ Bundler já está instalado"
fi

echo "✅ Dependências verificadas/instaladas"
echo "NOTA: PostgreSQL deve estar instalado externamente no sistema."

# --- 2. Instalar Ruby Gems ---
echo -e "\n📦 2. Instalando Ruby Gems..."
cd "$PG_MONITOR_BASE_DIR" || { echo "❌ Erro: Não foi possível entrar no diretório base."; exit 1; }

if [ ! -f "Gemfile" ]; then
    echo "❌ Erro: Gemfile não encontrado!"
    echo "   Clone o projeto do GitHub: git clone https://github.com/johnvithera01/pg_monitor.git"
    exit 1
fi

# Garantir que rbenv está carregado
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
rbenv shell 3.2.2

# Verificar versão do Ruby
echo "🔍 Usando Ruby: $(ruby -v)"
echo "🔍 Usando Bundler: $(bundle -v)"

bundle install
if [ $? -ne 0 ]; then
    echo "❌ Falha ao instalar gems. Verifique Ruby/Bundler."
    exit 1
fi
echo "✅ Gems instaladas com sucesso"

# --- 3. Criar estrutura de diretórios ---
echo -e "\n📁 3. Criando diretórios..."
mkdir -p "$CONFIG_DIR"

# Tentar criar diretório de logs com sudo, se falhar usar /tmp
if sudo mkdir -p "$LOG_DIR" 2>/dev/null && sudo chown $USER:$USER "$LOG_DIR" 2>/dev/null; then
    echo "✅ Diretório de logs criado: $LOG_DIR"
else
    LOG_DIR="${PG_MONITOR_BASE_DIR}/logs"
    mkdir -p "$LOG_DIR"
    echo "⚠️  Usando diretório local para logs: $LOG_DIR"
    echo "   (não foi possível criar /var/log/pg_monitor sem sudo)"
fi

echo "✅ Diretórios criados"

# --- 4. Criar arquivo .env ---
echo -e "\n⚙️  4. Criando arquivo .env..."
cat > "$ENV_FILE" << EOF
# pg_monitor v2.0 - Configuração de Ambiente
# Gerado automaticamente pelo setup_pg_monitor.sh

# Credenciais do PostgreSQL
PG_USER=$PG_USER
PG_PASSWORD=$PG_PASSWORD

# Senha do Email para alertas
EMAIL_PASSWORD=$EMAIL_PASSWORD
EOF

chmod 644 "$ENV_FILE"
echo "✅ Arquivo .env criado com suas configurações"

# --- 5. Configurar arquivo YAML ---
echo -e "\n⚙️  5. Configurando pg_monitor_config.yml..."
if [ ! -f "$PG_MONITOR_CONFIG_FILE" ]; then
    echo "❌ Erro: ${PG_MONITOR_CONFIG_FILE} não encontrado"
    exit 1
fi

# Fazer backup
cp "$PG_MONITOR_CONFIG_FILE" "${PG_MONITOR_CONFIG_FILE}.backup"

# Atualizar configurações usando sed (com cuidado para não substituir smtp_port)
sed -i.tmp "s|host: \".*\"|host: \"$PG_HOST\"|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "/^database:/,/^email:/ s|  port: .*|  port: $PG_PORT|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "s|name: \".*\"|name: \"$PG_DBNAME\"|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "s|sender_email: \".*\"|sender_email: \"$SENDER_EMAIL\"|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "s|receiver_email: \".*\"|receiver_email: \"$RECEIVER_EMAIL\"|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "s|smtp_port: .*|smtp_port: 587|" "$PG_MONITOR_CONFIG_FILE"
sed -i.tmp "s|log_file: \".*\"|log_file: \"${LOG_DIR}/pg_monitor.log\"|" "$PG_MONITOR_CONFIG_FILE"

# Remover arquivos temporários do sed
rm -f "${PG_MONITOR_CONFIG_FILE}.tmp"

echo "✅ Configuração YAML atualizada"
echo "   Backup salvo em: ${PG_MONITOR_CONFIG_FILE}.backup"

# --- 6. Testar Instalação ---
echo -e "\n🧪 6. Testando instalação..."
if ruby -c "$PG_MONITOR_RB_PATH" > /dev/null 2>&1; then
    echo "✅ Sintaxe do pg_monitor.rb OK"
else
    echo "❌ Erro de sintaxe no pg_monitor.rb"
    exit 1
fi

echo -e "\n🧪 7. Testando execução..."
cd "$PG_MONITOR_BASE_DIR"
if timeout 30 ruby "$PG_MONITOR_RB_PATH" high 2>&1 | tee /tmp/pg_monitor_test.log; then
    echo "✅ Teste de execução bem-sucedido!"
else
    echo "⚠️  Teste de execução falhou. Verifique os logs:"
    tail -20 /tmp/pg_monitor_test.log
    echo ""
    echo "Possíveis problemas:"
    echo "  - PostgreSQL não está acessível"
    echo "  - Credenciais incorretas"
    echo "  - Firewall bloqueando conexão"
fi

# --- 8. Configurar Cron Jobs ---
echo -e "\n⏰ 8. Configurando cron jobs..."
read -p "Deseja configurar cron jobs automaticamente? (s/N): " SETUP_CRON

if [[ "$SETUP_CRON" =~ ^[Ss]$ ]]; then
    # Criar arquivo temporário com os cron jobs
    CRON_TEMP=$(mktemp)
    crontab -l > "$CRON_TEMP" 2>/dev/null || true
    
    # Adicionar jobs se não existirem
    if ! grep -q "pg_monitor.rb high" "$CRON_TEMP"; then
        cat >> "$CRON_TEMP" << EOF

# pg_monitor - Monitoramento PostgreSQL
*/2 * * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb high >> ${LOG_DIR}/cron.log 2>&1
*/30 * * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb medium >> ${LOG_DIR}/cron.log 2>&1
0 */6 * * * cd ${PG_MONITOR_BASE_DIR} && ruby pg_monitor.rb low >> ${LOG_DIR}/cron.log 2>&1
EOF
        crontab "$CRON_TEMP"
        echo "✅ Cron jobs configurados!"
    else
        echo "⚠️  Cron jobs já existem, pulando..."
    fi
    
    rm -f "$CRON_TEMP"
else
    echo "⏭️  Pulando configuração de cron jobs"
fi

# --- 9. Resumo Final ---
echo ""
echo "========================================"
echo "✅ pg_monitor v2.0 - Instalação Completa!"
echo "========================================"
echo ""
echo "📊 Configuração Aplicada:"
echo "   PostgreSQL: $PG_HOST:$PG_PORT/$PG_DBNAME"
echo "   Usuário: $PG_USER"
echo "   Email: $SENDER_EMAIL → $RECEIVER_EMAIL"
echo ""
echo "📁 Arquivos Criados:"
echo "   ✅ $ENV_FILE"
echo "   ✅ $PG_MONITOR_CONFIG_FILE"
echo "   ✅ $LOG_DIR"
echo ""
if [[ "$SETUP_CRON" =~ ^[Ss]$ ]]; then
echo "⏰ Cron Jobs Ativos:"
echo "   ✅ Monitoramento crítico (a cada 2 min)"
echo "   ✅ Performance (a cada 30 min)"
echo "   ✅ Manutenção (a cada 6 horas)"
echo ""
fi
echo "📝 Comandos Úteis:"
echo "   # Testar manualmente"
echo "   ruby $PG_MONITOR_RB_PATH high"
echo ""
echo "   # Ver logs"
echo "   tail -f $LOG_DIR/cron.log"
echo ""
echo "   # Ver cron jobs"
echo "   crontab -l"
echo ""
echo "   # Editar configuração"
echo "   nano $PG_MONITOR_CONFIG_FILE"
echo ""
echo "📚 Documentação: README.md, DOCKER_INSTALL.md"
echo ""
echo "🎉 Tudo pronto! O monitoramento já está ativo!"