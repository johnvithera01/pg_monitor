#!/bin/bash

# quick-start.sh - Quick start script for pg_monitor

set -e

echo "🚀 pg_monitor Quick Start"
echo "========================="
echo

# Check if Docker is available
if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
    echo "✅ Docker detected - Using Docker installation"
    INSTALL_METHOD="docker"
else
    echo "⚠️  Docker not found - Using native installation"
    INSTALL_METHOD="native"
fi

echo

# Get user preferences
read -p "Enter your PostgreSQL host [localhost]: " PG_HOST
PG_HOST=${PG_HOST:-localhost}

read -p "Enter your PostgreSQL port [5432]: " PG_PORT
PG_PORT=${PG_PORT:-5432}

read -p "Enter your PostgreSQL database name [postgres]: " PG_DB
PG_DB=${PG_DB:-postgres}

read -p "Enter your PostgreSQL username: " PG_USER
if [ -z "$PG_USER" ]; then
    echo "❌ PostgreSQL username is required"
    exit 1
fi

read -s -p "Enter your PostgreSQL password: " PG_PASSWORD
echo
if [ -z "$PG_PASSWORD" ]; then
    echo "❌ PostgreSQL password is required"
    exit 1
fi

read -p "Enter your email for alerts: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "❌ Email is required for alerts"
    exit 1
fi

read -s -p "Enter your email app password: " EMAIL_PASSWORD
echo
if [ -z "$EMAIL_PASSWORD" ]; then
    echo "❌ Email password is required"
    exit 1
fi

echo
echo "🔧 Setting up pg_monitor..."

if [ "$INSTALL_METHOD" = "docker" ]; then
    # Docker setup
    echo "📦 Using Docker installation"
    
    # Create .env file
    cat > .env << EOF
PG_USER=$PG_USER
PG_PASSWORD=$PG_PASSWORD
EMAIL_PASSWORD=$EMAIL_PASSWORD
GRAFANA_PASSWORD=admin
POSTGRES_DB=$PG_DB
POSTGRES_USER=$PG_USER
POSTGRES_PASSWORD=$PG_PASSWORD
EOF

    # Update configuration if needed
    if [ "$PG_HOST" != "localhost" ] || [ "$PG_PORT" != "5432" ]; then
        echo "🔧 Updating configuration for external PostgreSQL..."
        
        # Create custom config
        cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml
        sed -i.bak "s/127.0.0.1/$PG_HOST/g" config/pg_monitor_config.yml
        sed -i.bak "s/5432/$PG_PORT/g" config/pg_monitor_config.yml
        sed -i.bak "s/postgres/$PG_DB/g" config/pg_monitor_config.yml
        
        # Update docker-compose to not start PostgreSQL
        cp docker-compose.yml docker-compose.yml.bak
        echo "⚠️  Using external PostgreSQL. Remove 'postgres' service from docker-compose.yml if needed."
    fi

    echo "🚀 Starting services..."
    docker-compose up -d

    echo
    echo "✅ pg_monitor is now running!"
    echo
    echo "📊 Access points:"
    echo "  • Prometheus metrics: http://localhost:9394/metrics"
    echo "  • Prometheus UI:      http://localhost:9090"
    echo "  • Grafana dashboards: http://localhost:3000 (admin/admin)"
    echo
    echo "🔍 Check status:"
    echo "  docker-compose ps"
    echo "  docker-compose logs -f pg_monitor"
    echo
    echo "🧪 Test monitoring:"
    echo "  docker-compose exec pg_monitor ruby pg_monitor.rb high"

else
    # Native setup
    echo "⚙️  Using native installation"
    
    # Install dependencies
    if command -v bundle &> /dev/null; then
        bundle install
    else
        echo "Installing bundler..."
        gem install bundler
        bundle install
    fi

    # Setup configuration
    cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml
    
    # Update config with user values
    sed -i.bak "s/127.0.0.1/$PG_HOST/g" config/pg_monitor_config.yml
    sed -i.bak "s/5432/$PG_PORT/g" config/pg_monitor_config.yml
    sed -i.bak "s/postgres/$PG_DB/g" config/pg_monitor_config.yml
    
    # Set environment variables
    cat > .env << EOF
export PG_USER="$PG_USER"
export PG_PASSWORD="$PG_PASSWORD"
export EMAIL_PASSWORD="$EMAIL_PASSWORD"
EOF

    echo "✅ Configuration complete!"
    echo
    echo "🔧 Load environment variables:"
    echo "  source .env"
    echo
    echo "🧪 Test connection:"
    echo "  make db-test-connection"
    echo
    echo "🚀 Start monitoring:"
    echo "  ruby pg_monitor.rb high"
    echo
    echo "📊 Start metrics server:"
    echo "  bundle exec puma -C config/puma.rb"
fi

echo
echo "📚 Documentation: https://github.com/johnvithera01/pg_monitor"
echo "🆘 Support: https://github.com/johnvithera01/pg_monitor/issues"
echo
echo "🎉 Happy monitoring!"
