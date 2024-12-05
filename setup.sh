#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to check if .env file exists
check_env() {
    if [ ! -f .env ]; then
        echo -e "${YELLOW}Creating .env file...${NC}"
        
        # Generate secure passwords
        DB_PASSWORD=$(generate_password)
        ADMIN_PASSWORD=$(generate_password)
        
        cat > .env << EOF
# Database Configuration
POSTGRES_DB=postgres
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_USER=odoo

# Odoo Configuration
# Comment out ports for production with NPM
ODOO_PORT=8069
CHAT_PORT=8072

# Deployment Mode (dev/prod)
DEPLOY_MODE=dev

# Admin password (for reference)
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF
        echo -e "${GREEN}.env file created with secure passwords${NC}"
        
        # Save passwords to a secure file
        cat > .env.secrets << EOF
Database Password: ${DB_PASSWORD}
Odoo Admin Password: ${ADMIN_PASSWORD}
EOF
        chmod 600 .env.secrets
        echo -e "${YELLOW}Passwords saved to .env.secrets${NC}"
    else
        echo -e "${GREEN}.env file exists${NC}"
    fi
}

# Function to create Odoo config
create_odoo_config() {
    if [ ! -d "etc" ]; then
        echo -e "${YELLOW}Creating Odoo configuration...${NC}"
        mkdir -p etc
        
        # Get admin password from .env file or generate new one
        ADMIN_PASSWORD=$(grep ADMIN_PASSWORD .env | cut -d '=' -f2 || generate_password)
        ADMIN_PASSWORD_HASH=$(generate_admin_hash "${ADMIN_PASSWORD}")
        
        cat > etc/odoo.conf << EOF
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
    else
        echo -e "${GREEN}Odoo configuration exists${NC}"
    fi
}

# Function to create necessary directories
create_directories() {
    mkdir -p {etc,postgresql,addons}
    chmod 777 postgresql # Ensure PostgreSQL has write permissions
    echo -e "${GREEN}Directories created/checked${NC}"
}

# Function to modify docker-compose for production
prepare_compose_file() {
    DEPLOY_MODE=$(grep DEPLOY_MODE .env | cut -d '=' -f2)
    
    if [ "$DEPLOY_MODE" = "prod" ]; then
        echo -e "${YELLOW}Preparing for production mode (NPM)...${NC}"
        # Comment out the ports section in docker-compose.yml
        sed -i.bak '/ports:/,+2 s/^/#/' docker-compose.yml
        echo -e "${GREEN}Ports have been commented out for NPM usage${NC}"
    else
        echo -e "${YELLOW}Preparing for development mode...${NC}"
        # Uncomment the ports section if it was commented
        sed -i.bak '/^#.*ports:/,+2 s/^#//' docker-compose.yml
        echo -e "${GREEN}Ports have been uncommented for direct access${NC}"
    fi
}

# Function to create backup script
create_backup_script() {
    cat > backup.sh << 'EOF'
#!/bin/bash

# Backup directory
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
docker-compose exec -T db pg_dump -U odoo postgres > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"

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
    chmod +x backup.sh
    echo -e "${GREEN}Backup script created${NC}"
}

# Main execution
echo -e "${YELLOW}Starting Odoo setup...${NC}"

# Create necessary directories
create_directories

# Check and create .env file
check_env

# Create Odoo configuration
create_odoo_config

# Check and create Docker network
check_network

# Prepare docker-compose file based on deployment mode
prepare_compose_file

# Create backup script
create_backup_script

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Important:${NC}"
echo -e "1. Review the configuration in etc/odoo.conf"
echo -e "2. Check .env.secrets for your passwords"
echo -e "3. For production deployment:"
echo -e "   - Set DEPLOY_MODE=prod in .env"
echo -e "   - Run setup.sh again to update configuration"
echo -e "   - Configure NPM with:"
echo -e "     * Main application: odoo:8069"
echo -e "     * Chat/Longpolling: odoo:8072 (enable WebSocket)"
echo -e "4. To start the containers:"
echo -e "   docker-compose up -d"
echo -e "5. Backup script created as backup.sh"
echo -e "\nSecrets file location: ${YELLOW}.env.secrets${NC}"
echo -e "Make sure to keep this file secure and backed up!"
