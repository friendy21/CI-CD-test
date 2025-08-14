#!/bin/bash
# setup.sh - Simple GitHub Secrets Setup
set -e

echo "================================================"
echo "     GitHub Secrets Setup for CI/CD Pipeline"
echo "================================================"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed!"
    echo ""
    echo "Please install it first:"
    echo "  macOS:  brew install gh"
    echo "  Ubuntu: sudo apt install gh"
    echo "  Other:  https://cli.github.com/manual/installation"
    exit 1
fi

# Check GitHub authentication
echo "📝 Checking GitHub authentication..."
if ! gh auth status &>/dev/null; then
    echo "Please authenticate with GitHub:"
    gh auth login
fi

echo "✅ GitHub CLI authenticated"
echo ""

# Get repository name
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
    echo "Enter your GitHub repository (e.g., friendy21/CI-CD-test):"
    read -r REPO
fi

echo "📦 Repository: $REPO"
echo ""

# Function to set secret
set_secret() {
    local name=$1
    local value=$2
    echo -n "  Setting $name... "
    if echo "$value" | gh secret set "$name" --repo="$REPO" 2>/dev/null; then
        echo "✅"
    else
        echo "❌ Failed"
        return 1
    fi
}

echo "================================================"
echo "         Docker Hub Configuration"
echo "================================================"
echo ""

# Docker Hub credentials
echo "Enter your Docker Hub username:"
read -r DOCKER_USERNAME

echo "Enter your Docker Hub Access Token (hidden):"
echo "  (Create one at: https://hub.docker.com/settings/security)"
read -rs DOCKER_TOKEN
echo ""

# Server configuration
echo ""
echo "================================================"
echo "         Server Configuration"
echo "================================================"
echo ""

echo "Enter your server IP address:"
read -r DROPLET_HOST

echo "Enter SSH username (default: root):"
read -r DROPLET_USER
DROPLET_USER="${DROPLET_USER:-root}"

echo "Enter SSH port (default: 22):"
read -r SSH_PORT
SSH_PORT="${SSH_PORT:-22}"

# SSH Key generation
echo ""
echo "================================================"
echo "         SSH Key Configuration"
echo "================================================"
echo ""

SSH_KEY_PATH="$HOME/.ssh/cicd_deploy_$(date +%s)"

echo "Generating SSH key pair..."
ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "github-actions-deploy" -q

echo ""
echo "📋 PUBLIC KEY - Add this to your server's ~/.ssh/authorized_keys:"
echo "================================================"
cat "${SSH_KEY_PATH}.pub"
echo "================================================"
echo ""

echo "To add the key to your server, run this command on your LOCAL machine:"
echo ""
echo "  ssh-copy-id -i ${SSH_KEY_PATH}.pub -p $SSH_PORT $DROPLET_USER@$DROPLET_HOST"
echo ""
echo "Or manually add the above public key to the server."
echo ""

read -p "Press Enter after you've added the public key to your server..."

# Test SSH connection
echo ""
echo "Testing SSH connection..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -p "$SSH_PORT" "$DROPLET_USER@$DROPLET_HOST" "echo 'SSH connection successful!'" 2>/dev/null; then
    echo "✅ SSH connection successful!"
else
    echo "⚠️  SSH connection failed. Please ensure the public key is added correctly."
    echo "    Continuing anyway..."
fi

# Read private key
DROPLET_SSH_KEY=$(<"$SSH_KEY_PATH")

# Set all secrets
echo ""
echo "================================================"
echo "         Setting GitHub Secrets"
echo "================================================"
echo ""

set_secret "DOCKER_USERNAME" "$DOCKER_USERNAME"
set_secret "DOCKER_TOKEN" "$DOCKER_TOKEN"
set_secret "DROPLET_HOST" "$DROPLET_HOST"
set_secret "DROPLET_USER" "$DROPLET_USER"
set_secret "DROPLET_SSH_KEY" "$DROPLET_SSH_KEY"
set_secret "SSH_PORT" "$SSH_PORT"

echo ""
echo "================================================"
echo "              Setup Complete!"
echo "================================================"
echo ""
echo "✅ All secrets have been configured!"
echo ""
echo "📝 Your SSH keys are saved at:"
echo "   Private: $SSH_KEY_PATH"
echo "   Public:  ${SSH_KEY_PATH}.pub"
echo ""
echo "🚀 Next steps:"
echo "   1. Delete the old workflow: rm .github/workflows/nomad-deploy.yml"
echo "   2. Commit and push your changes"
echo "   3. The CI/CD pipeline will run automatically"
echo ""
echo "🔒 Security reminders:"
echo "   - Keep your SSH private key secure"
echo "   - Never commit secrets to your repository"
echo "   - Rotate tokens regularly"
echo ""
echo "📦 To trigger deployment manually:"
echo "   git push origin main"
echo ""
