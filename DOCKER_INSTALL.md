# 🐳 Instalação Docker - pg_monitor

## 📋 Pré-requisitos

**IMPORTANTE:** Este Docker instala APENAS o `pg_monitor`. Você deve ter:

✅ **PostgreSQL instalado e rodando** no servidor (host ou outro container)  
✅ **Docker** instalado (versão 20.10+)  
✅ **Docker Compose** instalado (versão 1.29+)

---

## 🚀 Instalação Rápida

### 1. Clone o Repositório

```bash
git clone https://github.com/johnvithera01/pg_monitor.git
cd pg_monitor
```

### 2. Configure as Credenciais

```bash
# Copiar template de configuração
cp .env.example .env

# Editar com suas credenciais
nano .env
```

**Preencha no arquivo `.env`:**
```bash
PG_USER=seu_usuario_postgres
PG_PASSWORD=sua_senha_postgres
EMAIL_PASSWORD=sua_senha_app_email
```

### 3. Configure o Host do PostgreSQL

```bash
# Copiar template de configuração
cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml

# Editar configuração
nano config/pg_monitor_config.yml
```

**Configure o host do PostgreSQL:**
```yaml
database:
  host: "192.168.1.100"  # IP do servidor PostgreSQL
  port: 5432
  name: "seu_banco"      # Nome do banco a monitorar
```

### 4. Iniciar o pg_monitor

```bash
# Construir e iniciar containers
docker-compose up -d

# Verificar status
docker-compose ps

# Verificar logs
docker-compose logs -f pg_monitor
```

---

## 🔧 Configurações de Rede

### Opção 1: PostgreSQL no Host (Recomendado)

O `docker-compose.yml` usa `network_mode: "host"` por padrão, permitindo acesso direto ao PostgreSQL do host.

```yaml
# docker-compose.yml (já configurado)
services:
  pg_monitor:
    network_mode: "host"  # Acessa localhost do host
```

**Configure em `config/pg_monitor_config.yml`:**
```yaml
database:
  host: "localhost"  # ou "127.0.0.1"
  port: 5432
```

### Opção 2: PostgreSQL em Outro Container

Se seu PostgreSQL está em outro container:

```bash
# Editar docker-compose.yml
nano docker-compose.yml
```

**Altere para:**
```yaml
services:
  pg_monitor:
    # Remover: network_mode: "host"
    networks:
      - postgres_network  # Rede do PostgreSQL

networks:
  postgres_network:
    external: true  # Usar rede externa existente
```

**Configure em `config/pg_monitor_config.yml`:**
```yaml
database:
  host: "nome_do_container_postgres"  # Nome do container PostgreSQL
  port: 5432
```

### Opção 3: PostgreSQL em Servidor Remoto

```yaml
database:
  host: "192.168.1.100"  # IP do servidor remoto
  port: 5432
```

---

## 📊 Serviços Instalados

### Configuração Padrão (Apenas pg_monitor)

```bash
docker-compose up -d
```

**Serviços:**
- ✅ `pg_monitor` - Aplicação de monitoramento
- ✅ `pg_monitor_scheduler` - Cron jobs automáticos

**Portas:**
- `9394` - Métricas Prometheus

### Configuração Completa (Com Prometheus e Grafana)

```bash
# Usar arquivo de configuração completa
docker-compose -f docker-compose.full.yml up -d
```

**Serviços adicionais:**
- ✅ `prometheus` - Coleta de métricas
- ✅ `grafana` - Dashboards visuais

**Portas:**
- `9394` - Métricas pg_monitor
- `9090` - Prometheus UI
- `3000` - Grafana (admin/admin)

---

## 🧪 Testar Instalação

### 1. Verificar Containers

```bash
# Listar containers rodando
docker-compose ps

# Deve mostrar:
# pg_monitor           Up      0.0.0.0:9394->9394/tcp
# pg_monitor_scheduler Up
```

### 2. Verificar Logs

```bash
# Logs em tempo real
docker-compose logs -f pg_monitor

# Logs do scheduler
docker-compose logs -f pg_monitor_scheduler

# Últimas 100 linhas
docker-compose logs --tail=100 pg_monitor
```

### 3. Testar Conexão com PostgreSQL

```bash
# Executar teste dentro do container
docker-compose exec pg_monitor ruby -e "
  require 'pg'
  conn = PG.connect(
    host: 'localhost',
    port: 5432,
    dbname: 'postgres',
    user: ENV['PG_USER'],
    password: ENV['PG_PASSWORD']
  )
  puts 'Conexão OK!'
  puts conn.exec('SELECT version();').first['version']
  conn.close
"
```

### 4. Verificar Métricas

```bash
# Acessar endpoint de métricas
curl http://localhost:9394/metrics

# Verificar saúde
curl http://localhost:9394/health
```

### 5. Executar Monitoramento Manual

```bash
# Executar monitoramento dentro do container
docker-compose exec pg_monitor ruby pg_monitor.rb high

# Ver resultado
docker-compose logs pg_monitor
```

---

## 🔄 Comandos Úteis

### Gerenciamento de Containers

```bash
# Iniciar serviços
docker-compose up -d

# Parar serviços
docker-compose stop

# Reiniciar serviços
docker-compose restart

# Parar e remover containers
docker-compose down

# Reconstruir imagens
docker-compose build --no-cache
docker-compose up -d
```

### Visualizar Logs

```bash
# Logs em tempo real
docker-compose logs -f

# Logs de serviço específico
docker-compose logs -f pg_monitor

# Últimas N linhas
docker-compose logs --tail=50 pg_monitor
```

### Acessar Shell do Container

```bash
# Bash interativo
docker-compose exec pg_monitor bash

# Executar comando único
docker-compose exec pg_monitor ruby --version
```

### Atualizar Configuração

```bash
# Editar configuração
nano config/pg_monitor_config.yml

# Reiniciar para aplicar mudanças
docker-compose restart
```

---

## 🔍 Troubleshooting

### Erro: "Connection refused" ao PostgreSQL

**Problema:** Container não consegue conectar ao PostgreSQL

**Soluções:**

```bash
# 1. Verificar se PostgreSQL está rodando
sudo systemctl status postgresql

# 2. Verificar se PostgreSQL aceita conexões de rede
sudo nano /etc/postgresql/*/main/postgresql.conf
# Alterar: listen_addresses = '*'

# 3. Verificar pg_hba.conf
sudo nano /etc/postgresql/*/main/pg_hba.conf
# Adicionar: host all all 0.0.0.0/0 md5

# 4. Reiniciar PostgreSQL
sudo systemctl restart postgresql

# 5. Testar conexão do host
psql -h localhost -U seu_usuario -d seu_banco
```

### Erro: "Authentication failed"

**Problema:** Credenciais incorretas

**Soluções:**

```bash
# 1. Verificar variáveis de ambiente
docker-compose exec pg_monitor env | grep PG_

# 2. Verificar arquivo .env
cat .env

# 3. Recriar containers com novas credenciais
docker-compose down
docker-compose up -d
```

### Erro: "No such file or directory" para config

**Problema:** Arquivo de configuração não encontrado

**Soluções:**

```bash
# 1. Verificar se arquivo existe
ls -la config/pg_monitor_config.yml

# 2. Copiar template se não existir
cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml

# 3. Reiniciar containers
docker-compose restart
```

### Container para constantemente

**Problema:** Container reinicia em loop

**Soluções:**

```bash
# 1. Verificar logs de erro
docker-compose logs pg_monitor

# 2. Verificar configuração
docker-compose config

# 3. Reconstruir imagem
docker-compose build --no-cache
docker-compose up -d

# 4. Executar em modo interativo para debug
docker-compose run --rm pg_monitor bash
```

### Métricas não aparecem

**Problema:** Endpoint de métricas não responde

**Soluções:**

```bash
# 1. Verificar se porta está exposta
docker-compose ps

# 2. Verificar se serviço está rodando
curl http://localhost:9394/health

# 3. Verificar logs
docker-compose logs pg_monitor | grep -i error

# 4. Reiniciar serviço
docker-compose restart pg_monitor
```

---

## 📁 Estrutura de Arquivos

```
pg_monitor/
├── docker-compose.yml          # Configuração básica (apenas pg_monitor)
├── docker-compose.full.yml     # Configuração completa (com Prometheus/Grafana)
├── Dockerfile                  # Imagem Docker
├── .env                        # Variáveis de ambiente (criar a partir do .env.example)
├── .env.example               # Template de configuração
├── config/
│   └── pg_monitor_config.yml  # Configuração principal (criar a partir do .sample)
├── logs/                      # Logs da aplicação (criado automaticamente)
└── crontab                    # Agendamento de jobs
```

---

## 🎯 Próximos Passos

Após instalação bem-sucedida:

1. ✅ **Verificar logs**: `docker-compose logs -f pg_monitor`
2. ✅ **Testar métricas**: `curl http://localhost:9394/metrics`
3. ✅ **Configurar alertas**: Editar `config/pg_monitor_config.yml`
4. ✅ **Monitorar continuamente**: Scheduler já está rodando automaticamente
5. ✅ **(Opcional) Instalar Grafana**: `docker-compose -f docker-compose.full.yml up -d`

---

## 📞 Suporte

- **Documentação**: [README.md](README.md)
- **Instalação Tradicional**: [README_INSTALACAO.md](README_INSTALACAO.md)
- **Issues**: https://github.com/johnvithera01/pg_monitor/issues

---

**🎉 pg_monitor rodando em Docker! Seu PostgreSQL está sendo monitorado!**
