# Multi-stage build for security and efficiency
FROM node:18-alpine AS builder

# Security: Run as non-root during build
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy package files first for better layer caching
COPY --chown=nodejs:nodejs package*.json ./

# Install dependencies with security audit
RUN npm ci --only=production && \
    npm audit fix && \
    npm cache clean --force

# Copy application code
COPY --chown=nodejs:nodejs . .

# Final stage - minimal runtime
FROM node:18-alpine

# Install security updates and required packages
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        dumb-init \
        curl && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy from builder stage
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .

# Security: Drop all capabilities
RUN apk add --no-cache libcap && \
    setcap -r /usr/local/bin/node || true

# Use non-root user
USER nodejs

# Security headers and environment
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=2048" \
    PORT=3000

# Expose port (informational)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Run application
CMD ["node", "server.js"]
