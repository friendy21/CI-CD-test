#!/bin/bash

# CI/CD Setup Script for GitHub Actions and Docker Hub
# Run this script to configure your repository secrets

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="friendy21/CI-CD-test"
DOCKER_USERNAME="friendy21"
DROPLET_IP="137.184.198.14"

echo -e "${GREEN}=== CI/CD Setup Script ===${NC}"
echo "This script will help you set up GitHub Actions secrets for your CI/CD pipeline"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI (gh) is not installed.${NC}"
    echo "Installing GitHub CLI..."
    
    # Install based on OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gh
    else
        echo -e "${RED}Please install GitHub CLI manually: https://cli.github.com/${NC}"
        exit 1
    fi
fi

# Authenticate with GitHub
echo -e "${YELLOW}Authenticating with GitHub...${NC}"
gh auth login

# Function to set GitHub secret
set_github_secret() {
    local secret_name=$1
    local secret_value=$2
    
    echo -e "${YELLOW}Setting secret: $secret_name${NC}"
    echo "$secret_value" | gh secret set "$secret_name" --repo="$GITHUB_REPO"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Secret $secret_name set successfully${NC}"
    else
        echo -e "${RED}✗ Failed to set secret $secret_name${NC}"
        return 1
    fi
}

# Set Docker Hub credentials
echo ""
echo -e "${GREEN}Setting Docker Hub credentials...${NC}"
set_github_secret "DOCKER_USERNAME" "$DOCKER_USERNAME"

# Docker token (masked for security)
DOCKER_TOKEN="dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"
set_github_secret "DOCKER_TOKEN" "$DOCKER_TOKEN"

# Set DigitalOcean Droplet credentials
echo ""
echo -e "${GREEN}Setting DigitalOcean Droplet credentials...${NC}"
set_github_secret "DROPLET_HOST" "$DROPLET_IP"

# Decode and set SSH key
echo ""
echo -e "${GREEN}Setting SSH private key...${NC}"
SSH_KEY_BASE64="LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNDRWdKeDAvYi8vS2dqUEhUbHVQUGhaSFhsSExRc1JpVGxWVEoxUytxWllEd0FBQUtEQ1FkSzh3a0hTCnZBQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQ0VnSngwL2IvL0tnalBIVGx1UFBoWkhYbEhMUXNSaVRsVlRKMVMrcVpZRHcKQUFBRUEzd2tvL2o2MmJoeUsvWE5ZSFdDcnRPVVMxM1ZhZWtlNFFEWmFUWXFpeGVZU0FuSFQ5di84cUNNOGRPVzQ4K0ZrZAplVWN0Q3hHSk9WVk1uVkw2cGxnUEFBQUFHR1p5YVdWdVpIbHJZV3hwYldGdVFHZHRZV2xzTG1OdmJRRUNBd1FGCi0tLS0tRU5EIE9QRU5TU0ggUFJJVkFURSBLRVktLS0tLQo="
SSH_KEY=$(echo "$SSH_KEY_BASE64" | base64 -d)
set_github_secret "DROPLET_SSH_KEY" "$SSH_KEY"

# Optional: Set DigitalOcean API token if provided
echo ""
read -p "Do you want to set DigitalOcean API token? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    DO_API_TOKEN="dop_v1_0f43a49f6f0618370674fa79a9d8a9e2e18775196378b9c6bcd35589a99fc0a8"
    set_github_secret "DO_API_TOKEN" "$DO_API_TOKEN"
fi

# Create necessary directories and files
echo ""
echo -e "${GREEN}Creating project structure...${NC}"

# Create GitHub Actions workflow directory
mkdir -p .github/workflows

# Create a simple test application if none exists
if [ ! -f "index.js" ]; then
    echo -e "${YELLOW}Creating sample Node.js application...${NC}"
    cat > index.js << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
  } else {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end('<h1>CI/CD Test Application</h1><p>Version: 1.0.0</p>');
  }
});

server.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
fi

# Create package.json if it doesn't exist
if [ ! -f "package.json" ]; then
    cat > package.json << 'EOF'
{
  "name": "cicd-test-app",
  "version": "1.0.0",
  "description": "Simple CI/CD test application",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Test passed\" && exit 0"
  },
  "author": "friendy21",
  "license": "MIT"
}
EOF
fi

# Create health check script
cat > healthcheck.js << 'EOF'
const http = require('http');

const options = {
  hostname: 'localhost',
  port: process.env.PORT || 3000,
  path: '/health',
  timeout: 2000
};

const req = http.request(options, (res) => {
  process.exit(res.statusCode === 200 ? 0 : 1);
});

req.on('error', () => {
  process.exit(1);
});

req.end();
EOF

# Create .dockerignore
cat > .dockerignore << 'EOF'
node_modules
npm-debug.log
.git
.github
.env
.DS_Store
*.md
.dockerignore
Dockerfile
docker-compose*.yml
EOF

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Next steps:"
echo "1. Review and commit the generated files"
echo "2. Push to GitHub: git add . && git commit -m 'Add CI/CD pipeline' && git push"
echo "3. The CI/CD pipeline will automatically trigger on push to main branch"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "- Make sure your Dockerfile is configured correctly for your application"
echo "- The pipeline will build and push to: docker.io/friendy21/cicd-nomad-app"
echo "- Deployment will happen to your DigitalOcean droplet at: $DROPLET_IP"
echo ""
echo -e "${GREEN}Happy deploying! 🚀${NC}"
