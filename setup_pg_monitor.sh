#!/bin/bash

# --- Variáveis de Configuração ---
# O diretório onde o script pg_monitor.rb está localizado.
# Automaticamente definido para o diretório pai do script setup_pg_monitor.sh
PG_MONITOR_BASE_DIR="$(dirname "$(realpath "$0")")"

CONFIG_DIR="${PG_MONITOR_BASE_DIR}/config"
LOG_DIR="/var/log/pg_monitor"
PG_MONITOR_CONFIG_FILE="${CONFIG_DIR}/pg_monitor_config.yml"
PG_MONITOR_RB_PATH="${PG_MONITOR_BASE_DIR}/pg_monitor.rb"

echo "--- Iniciando a configuração do pg_monitor ---"
echo "Diretório base do pg_monitor: ${PG_MONITOR_BASE_DIR}"

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
echo -e "\n2. Instalando Ruby Gems (dependências do projeto)..."
cd "$PG_MONITOR_BASE_DIR" || { echo "Erro: Não foi possível entrar no diretório base do pg_monitor."; exit 1; }

# Criar Gemfile se não existir (para garantir a instalação correta)
if [ ! -f "Gemfile" ]; then
  echo "Criando Gemfile..."
  cat <<EOF > Gemfile
source 'https://rubygems.org'

gem 'pg'
gem 'json' # Geralmente parte da instalação padrão do Ruby, mas bom garantir
gem 'mail'
gem 'fileutils' # Geralmente parte da instalação padrão do Ruby, mas bom garantir
gem 'yaml' # Geralmente parte da instalação padrão do Ruby, mas bom garantir
EOF
fi

# Instalar gems usando Bundler
bundle install --full-index
if [ $? -ne 0 ]; then
    echo "Falha ao instalar Ruby Gems. Verifique sua instalação Ruby/Bundler e tente novamente."
    exit 1
fi
echo "Ruby Gems instaladas."

# --- 3. Criar estrutura de diretórios ---
echo -e "\n3. Criando estrutura de diretórios..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
echo "Diretórios '${CONFIG_DIR}' e '${LOG_DIR}' criados."

# --- 4. Mover arquivo de configuração ---
echo -e "\n4. Movendo arquivo de configuração..."
if [ -f "${PG_MONITOR_BASE_DIR}/pg_monitor_config.yml" ]; then
    echo "Movendo pg_monitor_config.yml para ${CONFIG_DIR}/..."
    mv "${PG_MONITOR_BASE_DIR}/pg_monitor_config.yml" "$PG_MONITOR_CONFIG_FILE"
    if [ $? -ne 0 ]; then
        echo "Falha ao mover pg_monitor_config.yml. Verifique as permissões."
        exit 1
    fi
    echo "pg_monitor_config.yml movido com sucesso."
elif [ ! -f "$PG_MONITOR_CONFIG_FILE" ]; then
    echo "Erro: 'pg_monitor_config.yml' não encontrado nem na raiz nem em ${CONFIG_DIR}/."
    echo "Por favor, crie um arquivo 'pg_monitor_config.yml' em ${CONFIG_DIR}/ com suas configurações."
    echo "Você pode usar 'pg_monitor_config.yml.sample' como modelo."
    exit 1
else
    echo "pg_monitor_config.yml já está em ${CONFIG_DIR}/."
fi

# --- 5. Definir permissões de diretórios ---
echo -e "\n5. Definindo permissões..."
# Garante que o diretório de logs seja gravável por qualquer usuário (ou ajuste para um usuário específico se preferir)
sudo chmod 777 "$LOG_DIR" # Permissão total temporária, ajuste conforme sua política de segurança
echo "Permissões para '${LOG_DIR}' ajustadas (chmod 777)."
echo "Recomendação: Considere ajustar as permissões do diretório de log para algo mais restritivo (${LOG_DIR}), como permissão de escrita apenas para o usuário que executará o cron job (ex: chmod 755 ${LOG_DIR} e chown user:group ${LOG_DIR})."

# --- 6. Instruções Finais ---
echo -e "\n--- Configuração do pg_monitor concluída! ---"
echo -e "\nPróximos passos IMPORTANTES:"
echo "1. Edite o arquivo de configuração: Abra e configure o arquivo ${PG_MONITOR_CONFIG_FILE} com as suas informações de banco de dados e e-mail."
echo "   ATENÇÃO: Substitua os placeholders como host, name, user, password, emails, e senhas de e-mail."
echo "   Lembre-se que as senhas de banco de dados e e-mail podem ser lidas de variáveis de ambiente (PG_USER, PG_PASSWORD, EMAIL_PASSWORD)."
echo "   Se você optar por variáveis de ambiente, remova as senhas do arquivo YML por segurança."
echo "2. Configure suas variáveis de ambiente (opcional, mas recomendado para senhas):"
echo "   Para maior segurança, defina as variáveis de ambiente PG_USER, PG_PASSWORD e EMAIL_PASSWORD (se aplicável) no ambiente do seu cron job."
echo "   Exemplo (no seu 'crontab -e', antes das linhas de execução do script):"
echo "   PG_USER=\"seu_usuario\""
echo "   PG_PASSWORD=\"sua_senha_do_bd\""
echo "   EMAIL_PASSWORD=\"sua_senha_do_email\""
echo "3. Adicione os jobs ao Crontab: Use 'crontab -e' e adicione as linhas de execução do script, ajustando o caminho:"
echo "   * * * * * /usr/bin/ruby ${PG_MONITOR_RB_PATH} high >> ${LOG_DIR}/pg_monitor_high.log 2>&1"
echo "   # Adicione as outras frequências conforme suas necessidades (medium, low, etc. - veja o how_use.txt)"
echo "   Certifique-se de que o caminho para o Ruby e para o script estão corretos em seu ambiente."
echo "4. Verifique os logs do PostgreSQL: Garanta que seu postgresql.conf esteja configurado para gerar logs úteis para o daily_log_scan (veja o postgres.conf de exemplo fornecido)."
echo -e "\nTudo pronto para monitorar seu PostgreSQL!"