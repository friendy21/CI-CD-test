#!/bin/bash
# setup-secure-secrets.sh
# Secure script to configure GitHub secrets without exposing credentials
set -euo pipefail

# Configuration
readonly GITHUB_REPO="${GITHUB_REPO:-friendy21/CI-CD-test}"
readonly REQUIRED_SECRETS=(
    "DOCKER_USERNAME"
    "DOCKER_TOKEN"
    "DROPLET_HOST"
    "DROPLET_USER"
    "DROPLET_SSH_KEY"
    "SSH_PORT"
    "STAGING_HOST"
    "STAGING_USER"
    "STAGING_SSH_KEY"
    "NOMAD_ADDR"
    "NOMAD_TOKEN"
    "SLACK_WEBHOOK_URL"
)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    for tool in gh ssh-keygen jq curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        
        # Provide installation instructions
        if [[ " ${missing_tools[*]} " =~ " gh " ]]; then
            echo "  GitHub CLI: https://cli.github.com/"
        fi
        if [[ " ${missing_tools[*]} " =~ " jq " ]]; then
            echo "  jq: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)"
        fi
        
        exit 1
    fi
    
    log "✓ All prerequisites met"
}

# Validate input
validate_input() {
    local input="$1"
    local type="$2"
    
    case "$type" in
        ip)
            if [[ ! "$input" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                return 1
            fi
            ;;
        port)
            if [[ ! "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt 65535 ]]; then
                return 1
            fi
            ;;
        username)
            if [[ ! "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
    
    return 0
}

# Generate SSH keypair
generate_ssh_keypair() {
    local key_name="$1"
    local key_path="$HOME/.ssh/${key_name}"
    
    if [[ -f "$key_path" ]]; then
        log_warning "SSH key already exists at $key_path"
        read -p "Do you want to regenerate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "$(<"$key_path")"
            return 0
        fi
        
        # Backup existing key
        mv "$key_path" "${key_path}.backup.$(date +%s)"
        mv "${key_path}.pub" "${key_path}.pub.backup.$(date +%s)"
    fi
    
    log "Generating new SSH keypair..."
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "${key_name}@github-actions" -q
    
    log "✓ SSH keypair generated"
    log_info "Public key (add this to your server's ~/.ssh/authorized_keys):"
    echo ""
    cat "${key_path}.pub"
    echo ""
    
    # Return private key
    echo "$(<"$key_path")"
}

# Test SSH connection
test_ssh_connection() {
    local host="$1"
    local user="$2"
    local port="$3"
    local key_path="$4"
    
    log "Testing SSH connection to ${user}@${host}:${port}..."
    
    if ssh -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -i "$key_path" \
           -p "$port" \
           "${user}@${host}" \
           "echo 'SSH connection successful'" 2>/dev/null; then
        log "✓ SSH connection successful"
        return 0
    else
        log_warning "SSH connection failed. Please ensure:"
        echo "  1. The public key is added to the server"
        echo "  2. The server is accessible"
        echo "  3. SSH service is running on port $port"
        return 1
    fi
}

# Set GitHub secret
set_github_secret() {
    local secret_name="$1"
    local secret_value="$2"
    
    log "Setting secret: $secret_name"
    
    if echo "$secret_value" | gh secret set "$secret_name" --repo="$GITHUB_REPO" 2>/dev/null; then
        log "✓ Secret $secret_name set successfully"
        return 0
    else
        log_error "Failed to set secret $secret_name"
        return 1
    fi
}

# Verify GitHub authentication
verify_github_auth() {
    log "Verifying GitHub authentication..."
    
    if ! gh auth status &>/dev/null; then
        log_warning "Not authenticated with GitHub CLI"
        log "Please authenticate with GitHub:"
        gh auth login
    else
        log "✓ GitHub authentication verified"
    fi
}

# Main setup function
main() {
    clear
    echo "========================================="
    echo "   Secure CI/CD Secrets Configuration"
    echo "========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Verify GitHub authentication
    verify_github_auth
    
    # Collect and validate inputs
    declare -A secrets
    
    # Docker Hub credentials
    echo ""
    log "Configure Docker Hub credentials:"
    while true; do
        read -p "  Docker Hub username: " docker_username
        if validate_input "$docker_username" "username"; then
            secrets["DOCKER_USERNAME"]="$docker_username"
            break
        else
            log_error "Invalid username format"
        fi
    done
    
    while true; do
        read -s -p "  Docker Hub token (hidden): " docker_token
        echo
        if [[ -n "$docker_token" ]]; then
            secrets["DOCKER_TOKEN"]="$docker_token"
            break
        else
            log_error "Token cannot be empty"
        fi
    done
    
    # Production server configuration
    echo ""
    log "Configure Production Server:"
    while true; do
        read -p "  Server IP address: " droplet_host
        if validate_input "$droplet_host" "ip"; then
            secrets["DROPLET_HOST"]="$droplet_host"
            break
        else
            log_error "Invalid IP address format"
        fi
    done
    
    while true; do
        read -p "  SSH username (default: root): " droplet_user
        droplet_user="${droplet_user:-root}"
        if validate_input "$droplet_user" "username"; then
            secrets["DROPLET_USER"]="$droplet_user"
            break
        else
            log_error "Invalid username format"
        fi
    done
    
    while true; do
        read -p "  SSH port (default: 22): " ssh_port
        ssh_port="${ssh_port:-22}"
        if validate_input "$ssh_port" "port"; then
            secrets["SSH_PORT"]="$ssh_port"
            break
        else
            log_error "Invalid port number"
        fi
    done
    
    # Generate SSH key for production
    echo ""
    log "Generating SSH key for production..."
    prod_ssh_key=$(generate_ssh_keypair "cicd_production_deploy")
    secrets["DROPLET_SSH_KEY"]="$prod_ssh_key"
    
    # Test SSH connection
    read -p "Have you added the public key to the server? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_ssh_connection "$droplet_host" "$droplet_user" "$ssh_port" "$HOME/.ssh/cicd_production_deploy"
    fi
    
    # Optional: Staging server configuration
    echo ""
    read -p "Do you want to configure a staging server? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Configure Staging Server:"
        read -p "  Staging server IP: " staging_host
        secrets["STAGING_HOST"]="$staging_host"
        
        read -p "  Staging SSH username (default: root): " staging_user
        staging_user="${staging_user:-root}"
        secrets["STAGING_USER"]="$staging_user"
        
        staging_ssh_key=$(generate_ssh_keypair "cicd_staging_deploy")
        secrets["STAGING_SSH_KEY"]="$staging_ssh_key"
    fi
    
    # Optional: Nomad configuration
    echo ""
    read -p "Do you want to configure Nomad? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Configure Nomad:"
        read -p "  Nomad server address: " nomad_addr
        secrets["NOMAD_ADDR"]="$nomad_addr"
        
        read -s -p "  Nomad token (hidden): " nomad_token
        echo
        secrets["NOMAD_TOKEN"]="$nomad_token"
    fi
    
    # Optional: Slack notifications
    echo ""
    read -p "Do you want to configure Slack notifications? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "  Slack webhook URL: " slack_webhook
        secrets["SLACK_WEBHOOK_URL"]="$slack_webhook"
    fi
    
    # Set all secrets in GitHub
    echo ""
    log "Setting GitHub secrets..."
    local failed_secrets=()
    
    for secret_name in "${!secrets[@]}"; do
        if ! set_github_secret "$secret_name" "${secrets[$secret_name]}"; then
            failed_secrets+=("$secret_name")
        fi
    done
    
    # Summary
    echo ""
    echo "========================================="
    echo "           Configuration Summary"
    echo "========================================="
    
    if [[ ${#failed_secrets[@]} -eq 0 ]]; then
        log "✅ All secrets configured successfully!"
        echo ""
        log_info "Next steps:"
        echo "  1. Ensure SSH public keys are added to servers"
        echo "  2. Commit and push your code"
        echo "  3. GitHub Actions will automatically deploy on push to main"
        echo ""
        log_warning "Security reminders:"
        echo "  • Never commit secrets to your repository"
        echo "  • Rotate Docker tokens regularly"
        echo "  • Use strong SSH keys (Ed25519 recommended)"
        echo "  • Enable 2FA on GitHub and Docker Hub"
        echo "  • Regularly audit your secrets"
    else
        log_error "Failed to set the following secrets:"
        printf '%s\n' "${failed_secrets[@]}"
        echo ""
        log_info "Please set these manually using GitHub UI or CLI"
    fi
    
    # Cleanup sensitive data from memory
    unset secrets
    unset docker_token
    unset nomad_token
    unset prod_ssh_key
    unset staging_ssh_key
}

# Run main function
main "$@"
