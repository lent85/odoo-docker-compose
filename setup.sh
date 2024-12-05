#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
SOURCE_DIR="$(pwd)"
DEPLOY_MODE="dev"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS] <target_directory>"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -m, --mode MODE      Deployment mode (dev/prod) [default: dev]"
    echo "  -s, --source DIR     Source directory [default: current directory]"
    echo
    echo "Example:"
    echo "  $0 -m prod /opt/odoo/runtime"
    echo "  $0 --mode dev --source /path/to/source /path/to/target"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Target directory is required${NC}"
    show_help
    exit 1
fi

if [ "$DEPLOY_MODE" != "dev" ] && [ "$DEPLOY_MODE" != "prod" ]; then
    echo -e "${RED}Error: Invalid mode. Use 'dev' or 'prod'${NC}"
    exit 1
fi

# Function to generate random password
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | cut -c1-16
}

# Function to generate admin password hash for Odoo
generate_admin_hash() {
    local password=$1
    python3 -c "import hashlib; print(hashlib.pbkdf2_hmac('sha512', b'$password', b'$password', 100000).hex())"
}

# Function to check if a network exists
check_network() {
    if ! docker network ls | grep -q "apps-network"; then
        echo -e "${YELLOW}Creating apps-network...${NC}"
        docker network create apps-network
    else
        echo -e "${GREEN}apps-network already exists${NC}"
    fi
}

# Function to setup target directory
setup_target_directory() {
    echo -e "${YELLOW}Setting up target directory: $TARGET_DIR${NC}"
    
    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR"
    
    # Create directory structure
    mkdir -p "$TARGET_DIR"/{etc,postgresql,addons,backups}
    chmod 777 "$TARGET_DIR/postgresql"

    # Copy necessary files from source
    if [ -d "$SOURCE_DIR/addons" ]; then
        cp -r "$SOURCE_DIR/addons"/* "$TARGET_DIR/addons/" 2>/dev/null || true
    fi
    
    # Copy docker-compose.yml
    cp "$SOURCE_DIR/docker-compose.yml" "$TARGET_DIR/"
    
    echo -e "${GREEN}Target directory structure created${NC}"
}

# Function to create .env file
create_env_file() {
    local target_env="$TARGET_DIR/.env"
    
    # Generate secure passwords
    DB_PASSWORD=$(generate_password)
    ADMIN_PASSWORD=$(generate_password)
    
    cat > "$target_env" << EOF
# Database Configuration
POSTGRES_DB=postgres
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_USER=odoo

# Odoo Configuration
# Comment out ports for production with NPM
ODOO_PORT=8069
CHAT_PORT=8072

# Deployment Mode (dev/prod)
DEPLOY_MODE=${DEPLOY_MODE}

# Admin password (for reference)
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF

    # Save passwords to a secure file
    cat > "$TARGET_DIR/.env.secrets" << EOF
Database Password: ${DB_PASSWORD}
Odoo Admin Password: ${ADMIN_PASSWORD}
EOF
    chmod 600 "$TARGET_DIR/.env.secrets"
    
    echo -e "${GREEN}.env files created${NC}"
}

# Function to create Odoo config
create_odoo_config() {
    local target_conf="$TARGET_DIR/etc/odoo.conf"
    
    # Get admin password from .env file or generate new one
    ADMIN_PASSWORD=$(grep ADMIN_PASSWORD "$TARGET_DIR/.env" | cut -d '=' -f2)
    ADMIN_PASSWORD_HASH=$(generate_admin_hash "${ADMIN_PASSWORD}")
    
    cat > "$target_conf" << EOF
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
admin_passwd = ${ADMIN_PASSWORD_HASH}
proxy_mode = True
workers = 4
max_cron_threads = 2
limit_time_cpu = 600
limit_time_real = 1200
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
EOF

    echo -e "${GREEN}Odoo configuration created${NC}"
}

# Function to create backup script
create_backup_script() {
    cat > "$TARGET_DIR/backup.sh" << 'EOF'
#!/bin/bash

# Backup directory
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
docker compose exec -T db pg_dump -U odoo postgres > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"

# Backup Odoo filestore
echo "Backing up Odoo filestore..."
tar -czf "$BACKUP_DIR/filestore_backup_$TIMESTAMP.tar.gz" ./postgresql

# Backup Odoo config and addons
echo "Backing up Odoo configuration and addons..."
tar -czf "$BACKUP_DIR/config_backup_$TIMESTAMP.tar.gz" ./etc ./addons

# Clean up old backups (keep last 7 days)
find "$BACKUP_DIR" -type f -mtime +7 -exec rm {} \;

echo "Backup completed: $TIMESTAMP"
EOF
    chmod +x "$TARGET_DIR/backup.sh"
    echo -e "${GREEN}Backup script created${NC}"
}

# Function to modify docker-compose for production
prepare_compose_file() {
    if [ "$DEPLOY_MODE" = "prod" ]; then
        echo -e "${YELLOW}Preparing for production mode (NPM)...${NC}"
        # Comment out the ports section in docker-compose.yml
        sed -i.bak '/ports:/,+2 s/^/#/' "$TARGET_DIR/docker-compose.yml"
        echo -e "${GREEN}Ports have been commented out for NPM usage${NC}"
    else
        echo -e "${YELLOW}Preparing for development mode...${NC}"
        # Uncomment the ports section if it was commented
        sed -i.bak '/^#.*ports:/,+2 s/^#//' "$TARGET_DIR/docker-compose.yml"
        echo -e "${GREEN}Ports have been uncommented for direct access${NC}"
    fi
}

# Create start script
create_start_script() {
    cat > "$TARGET_DIR/start.sh" << 'EOF'
#!/bin/bash
docker compose up -d
EOF
    chmod +x "$TARGET_DIR/start.sh"
    
    cat > "$TARGET_DIR/stop.sh" << 'EOF'
#!/bin/bash
docker compose down
EOF
    chmod +x "$TARGET_DIR/stop.sh"
    
    echo -e "${GREEN}Start/Stop scripts created${NC}"
}

# Main execution
echo -e "${YELLOW}Starting Odoo setup...${NC}"
echo -e "Source: ${GREEN}$SOURCE_DIR${NC}"
echo -e "Target: ${GREEN}$TARGET_DIR${NC}"
echo -e "Mode: ${GREEN}$DEPLOY_MODE${NC}"

# Setup target directory
setup_target_directory

# Create .env file
create_env_file

# Create Odoo configuration
create_odoo_config

# Check and create Docker network
check_network

# Prepare docker-compose file based on deployment mode
prepare_compose_file

# Create backup script
create_backup_script

# Create start/stop scripts
create_start_script

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Important:${NC}"
echo -e "1. Review the configuration in $TARGET_DIR/etc/odoo.conf"
echo -e "2. Check $TARGET_DIR/.env.secrets for your passwords"
echo -e "3. To start/stop Odoo:"
echo -e "   - cd $TARGET_DIR"
echo -e "   - ./start.sh"
echo -e "   - ./stop.sh"
echo -e "4. For production deployment with NPM:"
echo -e "   * Main application: odoo:8069"
echo -e "   * Chat/Longpolling: odoo:8072 (enable WebSocket)"
echo -e "5. Backup script: $TARGET_DIR/backup.sh"
echo -e "\nSecrets file location: ${YELLOW}$TARGET_DIR/.env.secrets${NC}"
echo -e "Make sure to keep this file secure and backed up!"
