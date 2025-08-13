#!/bin/bash

# Deployment script for DigitalOcean Droplet
# This script runs on the server to deploy the Docker container

set -e

# Configuration
DOCKER_IMAGE="friendy21/cicd-nomad-app:latest"
CONTAINER_NAME="app-container"
APP_PORT=3000
EXPOSE_PORT=80

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "Starting deployment process..."

# Update system packages
log "Updating system packages..."
apt-get update -qq

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    log "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    log "Docker installed successfully"
else
    log "Docker is already installed"
fi

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    log "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    log "Docker Compose installed successfully"
fi

# Login to Docker Hub
log "Logging in to Docker Hub..."
echo "dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U" | docker login -u friendy21 --password-stdin

# Pull the latest image
log "Pulling latest Docker image: $DOCKER_IMAGE"
docker pull $DOCKER_IMAGE

# Check if container is running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warning "Container $CONTAINER_NAME exists. Stopping and removing..."
    docker stop $CONTAINER_NAME || true
    docker rm $CONTAINER_NAME || true
fi

# Run the new container
log "Starting new container..."
docker run -d \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p $EXPOSE_PORT:$APP_PORT \
    -e NODE_ENV=production \
    -e PORT=$APP_PORT \
    --memory="512m" \
    --cpus="0.5" \
    --log-driver json-file \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    $DOCKER_IMAGE

# Wait for container to be healthy
log "Waiting for container to be healthy..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if docker ps | grep -q $CONTAINER_NAME; then
        # Check if the application is responding
        if curl -f http://localhost:$EXPOSE_PORT/health &>/dev/null; then
            log "Container is healthy and responding!"
            break
        fi
    fi
    
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
        error "Container failed to become healthy after $MAX_ATTEMPTS attempts"
        docker logs $CONTAINER_NAME
        exit 1
    fi
    
    sleep 2
done

# Clean up old images
log "Cleaning up old Docker images..."
docker image prune -af --filter "until=24h"

# Setup firewall rules if ufw is installed
if command -v ufw &> /dev/null; then
    log "Configuring firewall..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi

# Setup nginx as reverse proxy (optional)
if command -v nginx &> /dev/null; then
    log "Configuring nginx..."
    cat > /etc/nginx/sites-available/app << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$EXPOSE_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /health {
        access_log off;
        proxy_pass http://localhost:$EXPOSE_PORT/health;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
    log "Nginx configured as reverse proxy"
fi

# Display container status
log "Deployment complete! Container status:"
docker ps | grep $CONTAINER_NAME

# Show logs
log "Recent container logs:"
docker logs --tail 20 $CONTAINER_NAME

# Create update script
cat > /root/update-app.sh << 'EOF'
#!/bin/bash
docker pull friendy21/cicd-nomad-app:latest
docker stop app-container
docker rm app-container
docker run -d --name app-container --restart unless-stopped -p 80:3000 friendy21/cicd-nomad-app:latest
docker image prune -f
EOF
chmod +x /root/update-app.sh

log "Update script created at /root/update-app.sh"
log "Deployment completed successfully! 🚀"
log "Application is running at http://$HOSTNAME"
