# Multi-stage build for security and efficiency
# Stage 1: Dependencies
FROM node:18-alpine AS deps

# Install security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        python3 \
        make \
        g++ && \
    rm -rf /var/cache/apk/*

WORKDIR /app

# Copy package files for better caching
COPY package*.json ./

# Install production dependencies with security audit
RUN npm ci --only=production --ignore-scripts && \
    npm audit fix --force && \
    npm cache clean --force

# Stage 2: Builder
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev) for building
RUN npm ci --ignore-scripts

# Copy application code
COPY . .

# Build application if needed (uncomment if you have a build step)
# RUN npm run build

# Remove dev dependencies
RUN npm prune --production

# Stage 3: Security scanner
FROM aquasec/trivy:latest AS scanner

# Copy the dependencies for scanning
COPY --from=deps /app/node_modules /app/node_modules
COPY package*.json /app/

# Run security scan
RUN trivy fs --no-progress --security-checks vuln --severity HIGH,CRITICAL /app || true

# Stage 4: Final runtime image
FROM node:18-alpine AS runtime

# Install runtime dependencies and security tools
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        dumb-init \
        curl \
        ca-certificates && \
    rm -rf /var/cache/apk/*

# Create non-root user with specific UID/GID
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

# Set up working directory with proper permissions
WORKDIR /app
RUN chown -R nodejs:nodejs /app

# Copy production dependencies from deps stage
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application code
COPY --chown=nodejs:nodejs package*.json ./
COPY --chown=nodejs:nodejs . .

# Create necessary directories with proper permissions
RUN mkdir -p /app/logs /app/tmp && \
    chown -R nodejs:nodejs /app/logs /app/tmp && \
    chmod 750 /app/logs /app/tmp

# Security hardening
RUN chmod -R 550 /app && \
    chmod -R 750 /app/logs /app/tmp && \
    find /app -type f -name "*.sh" -exec chmod 550 {} \;

# Switch to non-root user
USER nodejs

# Security headers and environment
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=2048 --enable-source-maps" \
    NPM_CONFIG_LOGLEVEL=warn \
    PORT=3000

# Metadata labels
LABEL maintainer="your-email@example.com" \
      version="1.0.0" \
      description="Secure Node.js application" \
      security.scan="trivy" \
      org.opencontainers.image.source="https://github.com/friendy21/CI-CD-test"

# Expose port (informational)
EXPOSE 3000

# Health check with proper timeout and interval
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Run application with limited memory
CMD ["node", "--max-old-space-size=512", "server.js"]
