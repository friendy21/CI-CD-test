#!/bin/bash
set -euo pipefail

# Enable debug mode if DEBUG=1
[[ "${DEBUG:-0}" == "1" ]] && set -x

# Configuration - Use environment variables
readonly DOCKER_IMAGE="${DOCKER_IMAGE:-docker.io/friendy21/cicd-nomad-app:latest}"
readonly CONTAINER_BASE_NAME="${CONTAINER_NAME:-app-container}"
readonly HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
readonly HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-2}"
readonly GRACEFUL_SHUTDOWN_TIMEOUT="${GRACEFUL_SHUTDOWN_TIMEOUT:-30}"
readonly NETWORK_NAME="${NETWORK_NAME:-app-network}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Timestamp for unique naming
readonly TIMESTAMP=$(date +%s)
readonly NEW_CONTAINER="${CONTAINER_BASE_NAME}-${TIMESTAMP}"

# Logging function with timestamp
log() {
    local level="${2:-INFO}"
    local color="${GREEN}"
    
    case "$level" in
        ERROR) color="${RED}" ;;
        WARN)  color="${YELLOW}" ;;
        INFO)  color="${GREEN}" ;;
        DEBUG) color="${BLUE}" ;;
    esac
    
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $1${NC}" >&2
}

# Error handling with cleanup
error_exit() {
    log "$1" "ERROR"
    cleanup_failed_deployment
    exit 1
}

# Cleanup failed deployment
cleanup_failed_deployment() {
    log "Cleaning up failed deployment..." "WARN"
    
    # Remove the new container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${NEW_CONTAINER}$"; then
        docker stop "${NEW_CONTAINER}" 2>/dev/null || true
        docker rm "${NEW_CONTAINER}" 2>/dev/null || true
        log "Removed failed container: ${NEW_CONTAINER}" "INFO"
    fi
}

# Cleanup old resources
cleanup_old_resources() {
    log "Cleaning up old resources..." "INFO"
    
    # Remove old containers (keep last 2 versions)
    docker ps -a --format '{{.Names}}' | grep "^${CONTAINER_BASE_NAME}-[0-9]" | \
        sort -r | tail -n +3 | xargs -r docker rm -f 2>/dev/null || true
    
    # Clean up dangling images
    docker image prune -af --filter "until=24h" 2>/dev/null || true
    
    # Clean up unused volumes
    docker volume prune -f 2>/dev/null || true
    
    log "Cleanup completed" "INFO"
}

# Signal handler for graceful shutdown
trap 'log "Deployment interrupted" "WARN"; cleanup_failed_deployment; exit 130' INT TERM

# Verify Docker daemon
verify_docker() {
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker daemon is not running or not accessible"
    fi
    log "Docker daemon verified" "DEBUG"
}

# Create network if not exists
ensure_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
        log "Creating network: ${NETWORK_NAME}" "INFO"
        docker network create "${NETWORK_NAME}" || true
    fi
}

# Authenticate to Docker registry
docker_login() {
    if [[ -z "${DOCKER_USERNAME:-}" ]] || [[ -z "${DOCKER_TOKEN:-}" ]]; then
        log "Docker credentials not found, assuming public image or already logged in" "WARN"
        return 0
    fi
    
    log "Authenticating to Docker registry..." "INFO"
    echo "${DOCKER_TOKEN}" | docker login -u "${DOCKER_USERNAME}" --password-stdin || \
        error_exit "Docker login failed"
}

# Pull image with retry logic
pull_image() {
    local max_retries=3
    local retry_count=0
    
    log "Pulling image: ${DOCKER_IMAGE}" "INFO"
    
    while [ $retry_count -lt $max_retries ]; do
        if docker pull "${DOCKER_IMAGE}"; then
            log "Image pulled successfully" "INFO"
            
            # Verify image
            if ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
                error_exit "Image verification failed"
            fi
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log "Pull attempt $retry_count/$max_retries failed, retrying..." "WARN"
        sleep 5
    done
    
    error_exit "Failed to pull image after $max_retries attempts"
}

# Start new container
start_new_container() {
    log "Starting new container: ${NEW_CONTAINER}" "INFO"
    
    # Calculate resource limits based on system resources
    local memory_limit="${MEMORY_LIMIT:-512m}"
    local cpu_limit="${CPU_LIMIT:-0.5}"
    
    # Start container with comprehensive configuration
    docker run -d \
        --name "${NEW_CONTAINER}" \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        --memory="${memory_limit}" \
        --memory-swap="${memory_limit}" \
        --cpus="${cpu_limit}" \
        --pids-limit 100 \
        --security-opt no-new-privileges:true \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=64m \
        --tmpfs /app/tmp:rw,noexec,nosuid,size=64m \
        --health-cmd="curl -f http://localhost:3000/health || exit 1" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=3 \
        --health-start-period=30s \
        --label "deployment.version=${TIMESTAMP}" \
        --label "deployment.image=${DOCKER_IMAGE}" \
        --label "com.docker.compose.project=${CONTAINER_BASE_NAME}" \
        -e NODE_ENV="${NODE_ENV:-production}" \
        -e PORT="${PORT:-3000}" \
        -e LOG_LEVEL="${LOG_LEVEL:-info}" \
        -p "${STAGING_PORT:-3001}:3000" \
        "${DOCKER_IMAGE}" || error_exit "Failed to start new container"
    
    log "Container started, waiting for health check..." "INFO"
}

# Wait for container to be healthy
wait_for_health() {
    local container="$1"
    local retry_count=0
    
    while [ $retry_count -lt $HEALTH_CHECK_RETRIES ]; do
        local health_status=$(docker inspect -f '{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "unknown")
        
        case "$health_status" in
            healthy)
                log "Container ${container} is healthy!" "INFO"
                return 0
                ;;
            unhealthy)
                log "Container ${container} is unhealthy" "ERROR"
                docker logs --tail 50 "${container}"
                return 1
                ;;
            starting)
                log "Health check in progress (${retry_count}/${HEALTH_CHECK_RETRIES})..." "DEBUG"
                ;;
            *)
                log "Unknown health status: ${health_status}" "WARN"
                ;;
        esac
        
        retry_count=$((retry_count + 1))
        sleep $HEALTH_CHECK_DELAY
    done
    
    log "Health check timeout after ${HEALTH_CHECK_RETRIES} attempts" "ERROR"
    docker logs --tail 50 "${container}"
    return 1
}

# Verify application endpoints
verify_application() {
    local container="$1"
    local port="${2:-3001}"
    
    log "Verifying application endpoints..." "INFO"
    
    # Test health endpoint
    if ! curl -sf "http://localhost:${port}/health" >/dev/null; then
        log "Health endpoint verification failed" "ERROR"
        return 1
    fi
    
    # Test main endpoint (adjust as needed)
    if ! curl -sf "http://localhost:${port}/" >/dev/null; then
        log "Main endpoint verification failed" "ERROR"
        return 1
    fi
    
    log "Application verification successful" "INFO"
    return 0
}

# Switch traffic to new container
switch_traffic() {
    log "Switching traffic to new container..." "INFO"
    
    # Find current production container
    local current_container=$(docker ps --format '{{.Names}}' | grep "^${CONTAINER_BASE_NAME}$" || true)
    
    if [[ -n "${current_container}" ]]; then
        log "Found current container: ${current_container}" "INFO"
        
        # Graceful shutdown of old container
        log "Gracefully shutting down old container (timeout: ${GRACEFUL_SHUTDOWN_TIMEOUT}s)..." "INFO"
        docker stop --time="${GRACEFUL_SHUTDOWN_TIMEOUT}" "${current_container}" || true
        
        # Remove old container
        docker rm "${current_container}" || true
        log "Old container removed" "INFO"
    fi
    
    # Stop the new container to change port mapping
    docker stop "${NEW_CONTAINER}"
    
    # Commit the container to preserve state (optional)
    docker commit "${NEW_CONTAINER}" "${DOCKER_IMAGE}-deployed:${TIMESTAMP}" || true
    
    # Remove the staging container
    docker rm "${NEW_CONTAINER}"
    
    # Start production container with production port
    log "Starting production container..." "INFO"
    docker run -d \
        --name "${CONTAINER_BASE_NAME}" \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        --memory="${MEMORY_LIMIT:-512m}" \
        --memory-swap="${MEMORY_LIMIT:-512m}" \
        --cpus="${CPU_LIMIT:-0.5}" \
        --pids-limit 100 \
        --security-opt no-new-privileges:true \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=64m \
        --tmpfs /app/tmp:rw,noexec,nosuid,size=64m \
        --health-cmd="curl -f http://localhost:3000/health || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --label "deployment.version=${TIMESTAMP}" \
        --label "deployment.image=${DOCKER_IMAGE}" \
        --label "deployment.date=$(date -Iseconds)" \
        -e NODE_ENV="${NODE_ENV:-production}" \
        -e PORT="${PORT:-3000}" \
        -e LOG_LEVEL="${LOG_LEVEL:-info}" \
        -p "${PRODUCTION_PORT:-80}:3000" \
        "${DOCKER_IMAGE}" || error_exit "Failed to start production container"
    
    log "Traffic switched successfully" "INFO"
}

# Generate deployment report
generate_report() {
    log "Generating deployment report..." "INFO"
    
    cat <<EOF

===========================================
       DEPLOYMENT REPORT
===========================================
Timestamp:    $(date -Iseconds)
Image:        ${DOCKER_IMAGE}
Container:    ${CONTAINER_BASE_NAME}
Version:      ${TIMESTAMP}
Status:       SUCCESS
-------------------------------------------
Container Details:
$(docker ps --filter "name=${CONTAINER_BASE_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
-------------------------------------------
Resource Usage:
$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "${CONTAINER_BASE_NAME}")
===========================================

EOF
}

# Main deployment function
main() {
    log "Starting Blue-Green Deployment" "INFO"
    log "Configuration:" "INFO"
    log "  Image: ${DOCKER_IMAGE}" "INFO"
    log "  Container: ${CONTAINER_BASE_NAME}" "INFO"
    log "  Network: ${NETWORK_NAME}" "INFO"
    
    # Pre-deployment checks
    verify_docker
    ensure_network
    docker_login
    
    # Pull latest image
    pull_image
    
    # Start new container
    start_new_container
    
    # Wait for health check
    if ! wait_for_health "${NEW_CONTAINER}"; then
        error_exit "New container failed health check"
    fi
    
    # Verify application
    if ! verify_application "${NEW_CONTAINER}" "${STAGING_PORT:-3001}"; then
        error_exit "Application verification failed"
    fi
    
    # Switch traffic
    switch_traffic
    
    # Final verification
    sleep 5
    if ! wait_for_health "${CONTAINER_BASE_NAME}"; then
        error_exit "Production container failed final health check"
    fi
    
    # Cleanup
    cleanup_old_resources
    
    # Generate report
    generate_report
    
    log "Deployment completed successfully!" "INFO"
}

# Run main function
main "$@"
