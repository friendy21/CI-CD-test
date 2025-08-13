#!/bin/bash

# Manual deployment script - Run this on your DigitalOcean droplet
# Save this file on your server at /root/deploy.sh

set -e

# Configuration
DOCKER_USERNAME="friendy21"
DOCKER_TOKEN="dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"
DOCKER_IMAGE="docker.io/friendy21/cicd-nomad-app:latest"
CONTAINER_NAME="app-container"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting deployment...${NC}"

# Login to Docker Hub
echo -e "${YELLOW}Logging in to Docker Hub...${NC}"
echo "$DOCKER_TOKEN" | docker login -u $DOCKER_USERNAME --password-stdin

# Pull the latest image
echo -e "${YELLOW}Pulling latest image...${NC}"
docker pull $DOCKER_IMAGE

# Stop and remove existing container
echo -e "${YELLOW}Stopping existing container...${NC}"
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Run new container
echo -e "${YELLOW}Starting new container...${NC}"
docker run -d \
  --name $CONTAINER_NAME \
  --restart unless-stopped \
  -p 80:3000 \
  -e NODE_ENV=production \
  -e PORT=3000 \
  $DOCKER_IMAGE

# Wait for container to start
sleep 3

# Check if container is running
if docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    echo ""
    docker ps | grep $CONTAINER_NAME
    echo ""
    echo -e "${GREEN}Application is running at:${NC}"
    echo "http://$(curl -s ifconfig.me)"
    echo "http://137.184.198.14"
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    docker logs $CONTAINER_NAME
    exit 1
fi

# Clean up old images
echo -e "${YELLOW}Cleaning up old images...${NC}"
docker image prune -af

echo -e "${GREEN}🎉 Deployment complete!${NC}"
