# scripts/install.sh
#!/bin/bash

# pg_monitor Installation Script

set -e

echo "🚀 Installing pg_monitor v2.0..."

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root"
   exit 1
fi

# Check system requirements
log_info "Checking system requirements..."

# Check Ruby
if ! command -v ruby &> /dev/null; then
    log_error "Ruby is not installed. Please install Ruby 2.7+ first."
    exit 1
fi

ruby_version=$(ruby -v | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ $(echo "$ruby_version < 2.7" | bc -l) -eq 1 ]]; then
    log_error "Ruby version $ruby_version is too old. Please upgrade to Ruby 2.7+"
    exit 1
fi

log_success "Ruby $ruby_version found"

# Check Bundler
if ! command -v bundle &> /dev/null; then
    log_info "Installing Bundler..."
    gem install bundler
fi

# Check Docker (optional)
if command -v docker &> /dev/null; then
    log_success "Docker found"
    DOCKER_AVAILABLE=true
else
    log_warning "Docker not found. Docker installation will be skipped."
    DOCKER_AVAILABLE=false
fi

# Installation directory
INSTALL_DIR="${1:-/opt/pg_monitor}"
log_info "Installing to: $INSTALL_DIR"

# Create installation directory
sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

# Clone repository
log_info "Cloning repository..."
if [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    git pull
else
    git clone https://github.com/johnvithera01/pg_monitor.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Install dependencies
log_info "Installing Ruby dependencies..."
bundle install --without development test

# Setup configuration
log_info "Setting up configuration..."
if [ ! -f "config/pg_monitor_config.yml" ]; then
    cp config/pg_monitor_config.yml.sample config/pg_monitor_config.yml
    log_warning "Configuration file created. Please edit config/pg_monitor_config.yml"
fi

if [ ! -f ".env" ]; then
    cp .env.example .env
    log_warning "Environment file created. Please edit .env with your settings"
fi

# Create directories
sudo mkdir -p /var/log/pg_monitor
sudo chown $USER:$USER /var/log/pg_monitor

mkdir -p tmp/pg_monitor

# Create systemd service (optional)
read -p "Do you want to install systemd service? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installing systemd service..."
    sudo cp scripts/pg_monitor.service /etc/systemd/system/
    sudo systemctl daemon-reload
    log_success "Systemd service installed. Configure environment variables in /etc/systemd/system/pg_monitor.service"
fi

# Setup cron (optional)
read -p "Do you want to setup cron monitoring? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Setting up cron jobs..."
    sudo cp crontab /etc/cron.d/pg_monitor
    sudo chmod 644 /etc/cron.d/pg_monitor
    log_success "Cron jobs installed"
fi

# Docker setup (optional)
if [ "$DOCKER_AVAILABLE" = true ]; then
    read -p "Do you want to build Docker image? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Building Docker image..."
        docker build -t pg_monitor:latest .
        log_success "Docker image built"
    fi
fi

# Final instructions
log_success "Installation completed!"
echo
log_info "Next steps:"
echo "1. Edit configuration: nano $INSTALL_DIR/config/pg_monitor_config.yml"
echo "2. Set environment variables in $INSTALL_DIR/.env"
echo "3. Test connection: cd $INSTALL_DIR && make db-test-connection"
echo "4. Run monitoring: cd $INSTALL_DIR && ruby pg_monitor.rb high"
echo
if [ "$DOCKER_AVAILABLE" = true ]; then
    echo "Docker usage:"
    echo "  cd $INSTALL_DIR && make docker-run"
fi
echo
log_info "Documentation: https://github.com/johnvithera01/pg_monitor"
