#!/bin/bash
set -euo pipefail

# Configuration - Use environment variables
readonly DOCKER_IMAGE="${DOCKER_IMAGE:-docker.io/friendy21/cicd-nomad-app:latest}"
readonly CONTAINER_NAME="${CONTAINER_NAME:-app-container}"
readonly HEALTH_CHECK_RETRIES=10
readonly HEALTH_CHECK_DELAY=3

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Error handling
error_exit() {
    log "$1" "$RED" >&2
    exit 1
}

# Cleanup function
cleanup() {
    log "Cleaning up old images..." "$YELLOW"
    docker image prune -af --filter "until=24h"
}

trap cleanup EXIT

# Main deployment
main() {
    log "Starting secure deployment..." "$GREEN"
    
    # Verify Docker credentials from environment
    if [[ -z "${DOCKER_USERNAME:-}" ]] || [[ -z "${DOCKER_TOKEN:-}" ]]; then
        error_exit "Docker credentials not found in environment"
    fi
    
    # Login to Docker Hub
    log "Logging in to Docker Hub..." "$YELLOW"
    echo "${DOCKER_TOKEN}" | docker login -u "${DOCKER_USERNAME}" --password-stdin || \
        error_exit "Docker login failed"
    
    # Pull latest image
    log "Pulling latest image..." "$YELLOW"
    docker pull "${DOCKER_IMAGE}" || error_exit "Failed to pull image"
    
    # Verify image signature (if using Docker Content Trust)
    export DOCKER_CONTENT_TRUST=1
    
    # Blue-green deployment
    log "Starting blue-green deployment..." "$YELLOW"
    
    # Start new container
    docker run -d \
        --name "${CONTAINER_NAME}-new" \
        --restart unless-stopped \
        --memory="512m" \
        --memory-swap="1g" \
        --cpus="0.5" \
        --security-opt no-new-privileges \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --read-only \
        --tmpfs /tmp \
        -p 3001:3000 \
        -e NODE_ENV=production \
        -e PORT=3000 \
        "${DOCKER_IMAGE}" || error_exit "Failed to start new container"
    
    # Health check loop
    log "Waiting for health check..." "$YELLOW"
    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        if docker exec "${CONTAINER_NAME}-new" curl -f http://localhost:3000/health &>/dev/null; then
            log "Health check passed!" "$GREEN"
            break
        fi
        
        if [[ $i -eq $HEALTH_CHECK_RETRIES ]]; then
            docker logs "${CONTAINER_NAME}-new"
            docker stop "${CONTAINER_NAME}-new"
            docker rm "${CONTAINER_NAME}-new"
            error_exit "Health check failed after ${HEALTH_CHECK_RETRIES} attempts"
        fi
        
        sleep $HEALTH_CHECK_DELAY
    done
    
    # Switch traffic
    log "Switching traffic to new container..." "$YELLOW"
    
    # Stop old container
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    
    # Rename new container
    docker rename "${CONTAINER_NAME}-new" "${CONTAINER_NAME}"
    
    # Update port mapping (requires restart)
    docker stop "${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}-final" \
        --restart unless-stopped \
        --memory="512m" \
        --memory-swap="1g" \
        --cpus="0.5" \
        --security-opt no-new-privileges \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --read-only \
        --tmpfs /tmp \
        -p 80:3000 \
        -e NODE_ENV=production \
        -e PORT=3000 \
        "${DOCKER_IMAGE}"
    
    docker rm "${CONTAINER_NAME}"
    docker rename "${CONTAINER_NAME}-final" "${CONTAINER_NAME}"
    
    log "Deployment successful!" "$GREEN"
    docker ps | grep "${CONTAINER_NAME}"
}

# Run main function
main "$@"
