# Simplified Multi-stage Dockerfile for Testing
FROM node:18-alpine AS base

# Install security updates and required tools
RUN apk update && \
    apk upgrade && \
    apk add --no-cache curl ca-certificates dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# Copy application code
COPY . .

# Set ownership
RUN chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Environment variables
ENV NODE_ENV=production \
    PORT=3000

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init and start application
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
