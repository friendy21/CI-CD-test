#!/bin/bash
set -euo pipefail

# NEVER hardcode secrets in scripts!
readonly GITHUB_REPO="${GITHUB_REPO:-friendy21/CI-CD-test}"
readonly REQUIRED_SECRETS=(
    "DOCKER_USERNAME"
    "DOCKER_TOKEN"
    "DROPLET_HOST"
    "DROPLET_USER"
    "DROPLET_SSH_KEY"
    "SSH_PORT"
)

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    echo -e "${2:-$GREEN}$1${NC}"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v gh &> /dev/null; then
        log "Installing GitHub CLI..." "$YELLOW"
        # Installation commands here
    fi
    
    if ! command -v ssh-keygen &> /dev/null; then
        log "ssh-keygen is required" "$RED"
        exit 1
    fi
}

# Generate new SSH keypair
generate_ssh_key() {
    local key_path="$HOME/.ssh/cicd_deploy_key"
    
    if [[ ! -f "$key_path" ]]; then
        log "Generating new SSH keypair..." "$YELLOW"
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "cicd@github-actions"
        
        log "Public key (add this to your server):" "$GREEN"
        cat "${key_path}.pub"
        
        log "Press enter after adding the public key to your server..."
        read -r
    fi
    
    echo "$(<"$key_path")"
}

# Set GitHub secret securely
set_github_secret() {
    local secret_name=$1
    local secret_value=$2
    
    log "Setting secret: $secret_name" "$YELLOW"
    
    if echo "$secret_value" | gh secret set "$secret_name" --repo="$GITHUB_REPO"; then
        log "✓ Secret $secret_name set successfully" "$GREEN"
    else
        log "✗ Failed to set secret $secret_name" "$RED"
        return 1
    fi
}

# Main setup
main() {
    log "=== Secure CI/CD Setup ===" "$GREEN"
    
    check_prerequisites
    
    # Authenticate with GitHub
    log "Authenticating with GitHub..." "$YELLOW"
    gh auth login
    
    # Collect secrets securely
    log "Enter your Docker Hub username:" "$YELLOW"
    read -r docker_username
    
    log "Enter your Docker Hub token (hidden):" "$YELLOW"
    read -rs docker_token
    echo
    
    log "Enter your DigitalOcean droplet IP:" "$YELLOW"
    read -r droplet_host
    
    log "Enter SSH username (default: root):" "$YELLOW"
    read -r droplet_user
    droplet_user="${droplet_user:-root}"
    
    log "Enter SSH port (default: 22):" "$YELLOW"
    read -r ssh_port
    ssh_port="${ssh_port:-22}"
    
    # Generate or use existing SSH key
    ssh_key=$(generate_ssh_key)
    
    # Set all secrets
    set_github_secret "DOCKER_USERNAME" "$docker_username"
    set_github_secret "DOCKER_TOKEN" "$docker_token"
    set_github_secret "DROPLET_HOST" "$droplet_host"
    set_github_secret "DROPLET_USER" "$droplet_user"
    set_github_secret "DROPLET_SSH_KEY" "$ssh_key"
    set_github_secret "SSH_PORT" "$ssh_port"
    
    log "=== Setup Complete ===" "$GREEN"
    log "All secrets have been securely configured in GitHub" "$GREEN"
    log "Never commit secrets to your repository!" "$RED"
}

main "$@"
