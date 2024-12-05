#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <destination> <port> <chat_port> [build]"
    echo "  build: Optional parameter to use self-built image"
    exit 1
fi

DESTINATION=$1
PORT=$2
CHAT=$3
BUILD=${4:-"no"}  # Default to "no" if not provided
ENV_FILE="$DESTINATION/.env"
SECRET_FILE="$DESTINATION/.secret"

# Generate secure random passwords
ADMIN_PASS=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | head -c 20)
DB_PASS=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | head -c 20)

# Clone repository
git clone --depth=1 https://github.com/lent85/odoo-docker-compose "$DESTINATION" || {
    echo "Failed to clone repository"
    exit 1
}
rm -rf "$DESTINATION/.git"

# Create .env file with secure configuration
cat > "$ENV_FILE" << EOL
ODOO_PORT=$PORT
CHAT_PORT=$CHAT
POSTGRES_DB=postgres
POSTGRES_USER=odoo
POSTGRES_PASSWORD=$DB_PASS
ADMIN_PASSWORD=$ADMIN_PASS
EOL

# Update odoo.conf to use environment variables
cat > "$DESTINATION/etc/odoo.conf" << EOL
[options]
addons_path = /mnt/extra-addons
data_dir = /etc/odoo
admin_passwd = ${ADMIN_PASS}
logfile = /etc/odoo/odoo-server.log
dev_mode = reload
EOL

# Create required directories
mkdir -p "$DESTINATION/postgresql"
mkdir -p "$DESTINATION/addons"
mkdir -p "$DESTINATION/etc"

# Ensure the entrypoint script is executable
chmod +x "$DESTINATION/docker/odoo/entrypoint.sh"

# Create requirements.txt if it doesn't exist
touch "$DESTINATION/etc/requirements.txt"

# Set proper permissions
sudo chown -R "$(id -u):$(id -g)" "$DESTINATION"
chmod -R 700 "$DESTINATION"
chmod 600 "$ENV_FILE"

# Store credentials securely
cat > "$SECRET_FILE" << EOL
Odoo Master Password: $ADMIN_PASS
Database Password: $DB_PASS
EOL
chmod 600 "$SECRET_FILE"

# Configure inotify if on Linux
if [[ "$OSTYPE" != "darwin"* ]]; then
    if ! grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
        echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
    fi
fi

# Start Odoo
cd "$DESTINATION"
if [ "$BUILD" = "build" ]; then
    echo "Using self-built image..."
    docker-compose -f docker-compose.build.yml up -d
else
    echo "Using DockerHub image..."
    docker-compose up -d
fi

echo "Odoo is starting up. You can access it at:"
echo "Main URL: http://localhost:$PORT"
echo "Chat URL: http://localhost:$CHAT"
echo "Credentials are saved in: $SECRET_FILE"
