#!/bin/bash
# scripts/deploy-production.sh
# Secure deployment script for production
set -euo pipefail

# Accept parameters from CI/CD
readonly IMAGE="${1:?Image parameter required}"
readonly DOCKER_USERNAME="${2:?Docker username required}"
readonly DOCKER_TOKEN="${3:?Docker token required}"

# Configuration
readonly CONTAINER_NAME="app-container"
readonly HEALTH_CHECK_TIMEOUT=60
readonly HEALTH_CHECK_INTERVAL=2
readonly MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
readonly CPU_LIMIT="${CPU_LIMIT:-0.5}"
readonly PORT="${PORT:-3000}"

# Color output
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1" >&2
    exit 1
}

# Docker login
log "Authenticating with Docker Hub..."
echo "${DOCKER_TOKEN}" | docker login -u "${DOCKER_USERNAME}" --password-stdin || error_exit "Docker login failed"

# Pull new image with retry
log "Pulling image: ${IMAGE}"
retry_count=0
max_retries=3

while [ $retry_count -lt $max_retries ]; do
    if docker pull "${IMAGE}"; then
        log "Image pulled successfully"
        break
    fi
    retry_count=$((retry_count + 1))
    log "Pull attempt $retry_count/$max_retries failed, retrying..."
    sleep 5
done

[ $retry_count -eq $max_retries ] && error_exit "Failed to pull image after $max_retries attempts"

# Blue-green deployment
log "Starting blue-green deployment..."

# Generate unique name for new container
NEW_CONTAINER="${CONTAINER_NAME}-$(date +%s)"

# Start new container
log "Starting new container: ${NEW_CONTAINER}"
docker run -d \
    --name "${NEW_CONTAINER}" \
    --restart unless-stopped \
    --memory="${MEMORY_LIMIT}" \
    --memory-swap="${MEMORY_LIMIT}" \
    --cpus="${CPU_LIMIT}" \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --health-cmd="curl -f http://localhost:${PORT}/health || exit 1" \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=3 \
    --health-start-period=30s \
    -p 8080:${PORT} \
    -e NODE_ENV=production \
    -e PORT=${PORT} \
    --label "deployment.timestamp=$(date -Iseconds)" \
    --label "deployment.version=${IMAGE##*@}" \
    "${IMAGE}" || error_exit "Failed to start new container"

# Wait for health check
log "Waiting for container to be healthy..."
health_check_elapsed=0

while [ $health_check_elapsed -lt $HEALTH_CHECK_TIMEOUT ]; do
    health_status=$(docker inspect -f '{{.State.Health.Status}}' "${NEW_CONTAINER}" 2>/dev/null || echo "unknown")
    
    if [ "$health_status" = "healthy" ]; then
        log "New container is healthy!"
        
        # Find old container
        OLD_CONTAINER=$(docker ps -q -f "name=^${CONTAINER_NAME}$" || true)
        
        # Switch traffic
        if [ -n "${OLD_CONTAINER}" ]; then
            log "Stopping old container..."
            docker stop --time=30 "${CONTAINER_NAME}" || true
            docker rm "${CONTAINER_NAME}" || true
        fi
        
        # Rename new container to production name
        docker stop "${NEW_CONTAINER}"
        docker rm "${NEW_CONTAINER}"
        
        # Start production container on port 80
        docker run -d \
            --name "${CONTAINER_NAME}" \
            --restart unless-stopped \
            --memory="${MEMORY_LIMIT}" \
            --memory-swap="${MEMORY_LIMIT}" \
            --cpus="${CPU_LIMIT}" \
            --security-opt no-new-privileges:true \
            --cap-drop ALL \
            --cap-add NET_BIND_SERVICE \
            --health-cmd="curl -f http://localhost:${PORT}/health || exit 1" \
            --health-interval=30s \
            --health-timeout=10s \
            --health-retries=3 \
            -p 80:${PORT} \
            -e NODE_ENV=production \
            -e PORT=${PORT} \
            --label "deployment.timestamp=$(date -Iseconds)" \
            --label "deployment.version=${IMAGE##*@}" \
            "${IMAGE}" || error_exit "Failed to start production container"
        
        log "Deployment completed successfully!"
        
        # Cleanup old images
        docker image prune -af --filter "until=24h" || true
        
        # Show container status
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        exit 0
    fi
    
    if [ "$health_status" = "unhealthy" ]; then
        log "Container is unhealthy. Logs:"
        docker logs --tail 50 "${NEW_CONTAINER}"
        docker stop "${NEW_CONTAINER}" || true
        docker rm "${NEW_CONTAINER}" || true
        error_exit "New container failed health check"
    fi
    
    sleep $HEALTH_CHECK_INTERVAL
    health_check_elapsed=$((health_check_elapsed + HEALTH_CHECK_INTERVAL))
done

# Timeout reached
log "Health check timeout after ${HEALTH_CHECK_TIMEOUT} seconds"
docker logs --tail 50 "${NEW_CONTAINER}"
docker stop "${NEW_CONTAINER}" || true
docker rm "${NEW_CONTAINER}" || true
error_exit "Deployment failed - health check timeout"
