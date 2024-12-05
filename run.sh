#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
        cat > .env << EOF
# Database Configuration
POSTGRES_DB=postgres
POSTGRES_PASSWORD=odoo_pw
POSTGRES_USER=odoo

# Odoo Configuration
# Comment out ports for production with NPM
ODOO_PORT=8069
CHAT_PORT=8072

# Deployment Mode (dev/prod)
DEPLOY_MODE=dev
EOF
        echo -e "${GREEN}.env file created${NC}"
    else
        echo -e "${GREEN}.env file exists${NC}"
    fi
}

# Function to create Odoo config
create_odoo_config() {
    if [ ! -d "etc" ]; then
        echo -e "${YELLOW}Creating Odoo configuration...${NC}"
        mkdir -p etc
        cat > etc/odoo.conf << EOF
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
admin_passwd = admin
EOF
        echo -e "${GREEN}Odoo configuration created${NC}"
    else
        echo -e "${GREEN}Odoo configuration exists${NC}"
    fi
}

# Function to create necessary directories
create_directories() {
    mkdir -p {etc,postgresql,addons}
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

# Main execution
echo -e "${YELLOW}Starting Odoo deployment setup...${NC}"

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

# Start the containers
echo -e "${YELLOW}Starting containers...${NC}"
docker-compose down
docker-compose up -d

# Check container status
echo -e "${YELLOW}Checking container status...${NC}"
docker-compose ps

echo -e "${GREEN}Setup complete!${NC}"

# Print access information
if [ "$(grep DEPLOY_MODE .env | cut -d '=' -f2)" = "dev" ]; then
    ODOO_PORT=$(grep ODOO_PORT .env | cut -d '=' -f2)
    echo -e "${GREEN}Odoo is accessible at:${NC}"
    echo -e "Main application: ${YELLOW}http://localhost:${ODOO_PORT}${NC}"
    echo -e "Chat/Longpolling: ${YELLOW}http://localhost:$(grep CHAT_PORT .env | cut -d '=' -f2)${NC}"
else
    echo -e "${GREEN}Odoo is configured for NPM access${NC}"
    echo -e "Please configure your proxy host in NPM with:"
    echo -e "- Main application: ${YELLOW}odoo:8069${NC}"
    echo -e "- Chat/Longpolling: ${YELLOW}odoo:8072${NC}"
fi
