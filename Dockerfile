# Simple Dockerfile for testing CI/CD pipeline
# This version doesn't require any package files

FROM node:18-alpine

# Install useful tools
RUN apk add --no-cache curl dumb-init

# Create app directory
WORKDIR /app

# Create a simple Node.js app inline (no external files needed)
RUN echo 'const http = require("http"); \
const port = process.env.PORT || 3000; \
const version = process.env.APP_VERSION || "1.0.0"; \
const server = http.createServer((req, res) => { \
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`); \
  if (req.url === "/health") { \
    res.writeHead(200, {"Content-Type": "text/plain"}); \
    res.end("OK"); \
  } else if (req.url === "/") { \
    res.writeHead(200, {"Content-Type": "text/html"}); \
    res.end(`<!DOCTYPE html> \
<html> \
<head><title>CI/CD Test</title></head> \
<body style="font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);"> \
  <div style="text-align: center; padding: 2rem; background: white; border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);"> \
    <h1 style="color: #333;">🚀 CI/CD Pipeline Working!</h1> \
    <p style="color: #666;">Version: ${version}</p> \
    <p style="color: #666;">Container ID: ${process.env.HOSTNAME || "unknown"}</p> \
    <p style="color: #666;">Timestamp: ${new Date().toISOString()}</p> \
  </div> \
</body> \
</html>`); \
  } else { \
    res.writeHead(404, {"Content-Type": "text/plain"}); \
    res.end("Not Found"); \
  } \
}); \
server.listen(port, () => { \
  console.log(`Server running on port ${port}`); \
  console.log(`Health check available at http://localhost:${port}/health`); \
});' > /app/server.js

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Run the application
CMD ["node", "/app/server.js"]
