# Odoo Docker Compose Setup

This repository provides a streamlined setup for running Odoo using Docker Compose, with options for both standard deployment and customized builds.

## Features

- Odoo 18.0 with PostgreSQL 17
- Choice between official DockerHub image and custom build
- Secure password generation
- Volume mapping for addons and configuration
- Automatic environment setup
- Support for custom Python packages
- Development mode enabled by default

## Prerequisites

- Docker
- Docker Compose
- Git
- Bash shell
- sudo privileges (for Linux systems)

## Directory Structure

```
.
├── .env.template
├── docker-compose.yml
├── docker-compose.build.yml
├── run.sh
├── docker/
│   └── odoo/
│       ├── Dockerfile
│       └── entrypoint.sh
├── etc/
│   ├── odoo.conf.template
│   └── requirements.txt
├── addons/
│   └── .gitkeep
└── .gitignore
```

## Quick Start

1. Clone this repository:
```bash
git clone https://github.com/lent85/odoo-docker-compose.git
cd odoo-docker-compose
```

2. Make the run script executable:
```bash
chmod +x run.sh
```

3. Run the setup script:

For standard deployment (using DockerHub image):
```bash
./run.sh /path/to/destination 8069 8072
```

For custom build deployment:
```bash
./run.sh /path/to/destination 8069 8072 build
```

Parameters:
- First argument: Destination path
- Second argument: Main Odoo port (default: 8069)
- Third argument: Chat port (default: 8072)
- Fourth argument (optional): Use "build" for custom build

## Configuration

### Environment Variables

The following environment variables are automatically configured in `.env`:

- `ODOO_PORT`: Main Odoo web interface port
- `CHAT_PORT`: Odoo live chat port
- `POSTGRES_DB`: PostgreSQL database name
- `POSTGRES_USER`: PostgreSQL user
- `POSTGRES_PASSWORD`: Auto-generated secure password
- `ADMIN_PASSWORD`: Auto-generated admin password

### Custom Python Packages

To add custom Python packages:

1. Edit `etc/requirements.txt`
2. Add your required packages
3. Restart the containers

### Custom Addons

Place your custom Odoo modules in the `addons` directory. They will be automatically detected by Odoo.

## Usage

### Starting the Environment

The environment starts automatically after running the setup script. To manually control the environment:

```bash
# Start the environment
docker-compose up -d

# Stop the environment
docker-compose down

# View logs
docker-compose logs -f

# Restart the environment
docker-compose restart
```

### Accessing Odoo

- Main Interface: `http://localhost:8069` (or your configured port)
- Live Chat: `http://localhost:8072` (or your configured port)

Initial database creation credentials are stored in `.secret` file in your destination directory.

### Development Mode

Development mode is enabled by default in `odoo.conf`, allowing for:
- Module hot-reloading
- Debug mode
- Developer tools access

## Security

- Secure passwords are automatically generated
- Credentials are stored in a protected `.secret` file
- Proper file permissions are set automatically
- Environment variables are secured

## Maintenance

### Backup

To backup your data:

```bash
# Stop the environment
docker-compose down

# Backup the postgresql directory
tar -czf odoo_data_backup.tar.gz postgresql/

# Backup custom addons
tar -czf odoo_addons_backup.tar.gz addons/
```

### Updates

For the DockerHub version:
```bash
docker-compose down
docker-compose pull
docker-compose up -d
```

For the custom build version:
```bash
docker-compose -f docker-compose.build.yml down
docker-compose -f docker-compose.build.yml build --no-cache
docker-compose -f docker-compose.build.yml up -d
```

## Troubleshooting

### Common Issues

1. **Port already in use**
   - Change the ports in your `.env` file
   - Restart the environment

2. **Permission Issues**
   ```bash
   sudo chown -R $(id -u):$(id -g) /path/to/destination
   ```

3. **Inotify Watches Limit (Linux)**
   - Automatically configured by the setup script
   - Manual configuration:
   ```bash
   echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

### Logs

View logs for debugging:
```bash
# All services
docker-compose logs -f

# Odoo only
docker-compose logs -f web

# PostgreSQL only
docker-compose logs -f db
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
