# Multi-stage build for security and efficiency
# Stage 1: Dependencies
FROM node:20-alpine AS dependencies
WORKDIR /tmp
COPY package*.json ./
RUN npm ci --only=production && \
    npm cache clean --force

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && \
    npm prune --production

# Stage 3: Security Scanner
FROM aquasec/trivy:latest AS scanner
COPY --from=builder /app /app
RUN trivy fs --no-progress --security-checks vuln,config --severity HIGH,CRITICAL /app

# Stage 4: Production
FROM node:20-alpine AS production

# Security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        dumb-init \
        curl \
        ca-certificates && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy dependencies and application
COPY --from=dependencies --chown=nodejs:nodejs /tmp/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Security hardening
RUN chmod -R 755 /app && \
    find /app -type d -exec chmod 755 {} \; && \
    find /app -type f -exec chmod 644 {} \;

# Add metadata
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.title="CI/CD Nomad App" \
      org.opencontainers.image.description="Production-ready containerized application" \
      org.opencontainers.image.vendor="friendy21" \
      org.opencontainers.image.licenses="MIT"

# Environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    NODE_OPTIONS="--max-old-space-size=512"

# Switch to non-root user
USER nodejs

# Expose port (informational)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node /app/healthcheck.js || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Run application
CMD ["node", "dist/server.js"]
