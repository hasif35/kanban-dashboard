
# Stage 1: Build application
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build


# Stage 2: Secure production runtime
FROM nginxinc/nginx-unprivileged:alpine AS runtime

# Copy only production artifacts
COPY --from=builder /app/dist /usr/share/nginx/html

# Explicitly run as non-root user
USER 101

# Application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

