# OpenClaw on Azure Container Apps
# Production-optimized Dockerfile with health checks and proper logging

FROM node:22-slim AS base

# Build arguments for versioning
ARG OPENCLAW_VERSION=latest
ARG BUILD_DATE
ARG VCS_REF

# Labels for container metadata
LABEL org.opencontainers.image.title="OpenClaw" \
      org.opencontainers.image.description="OpenClaw AI Agent Gateway for Azure Container Apps" \
      org.opencontainers.image.version="${OPENCLAW_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="OpenClaw" \
      org.opencontainers.image.source="https://github.com/openclaw/openclaw"

# Set environment variables
ENV NODE_ENV=production \
    OPENCLAW_WORKSPACE=/data/workspace \
    OPENCLAW_CONFIG=/data/config \
    OPENCLAW_LOG_LEVEL=info \
    BROWSER_PATH=/usr/bin/chromium \
    # Disable Chromium sandbox (required in containers)
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    # Azure Container Apps health check paths
    HEALTH_CHECK_PATH=/health \
    METRICS_PATH=/metrics \
    # Prevent npm update checks
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    # Use production npm settings
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    # Suppress npm deprecation warnings from transitive deps
    NODE_NO_WARNINGS=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    git \
    curl \
    ca-certificates \
    gnupg \
    dumb-init \
    su-exec \
    # Chromium for browser automation
    chromium \
    # Fonts for proper rendering
    fonts-liberation \
    fonts-noto-color-emoji \
    # Audio/video support
    libpulse0 \
    libasound2 \
    # Image processing
    libpng-dev \
    libjpeg-dev \
    # Networking
    iputils-ping \
    dnsutils \
    # Security
    openssl \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create non-root user for security (use UID/GID 1001 to avoid conflicts with node group)
RUN groupadd --gid 1001 openclaw \
    && useradd --uid 1001 --gid openclaw --shell /bin/bash --create-home openclaw

# Create data directories with proper permissions
RUN mkdir -p /data/workspace /data/config /data/logs /data/cache \
    && chown -R openclaw:openclaw /data

# Install OpenClaw globally (suppress deprecation warnings from transitive deps)
RUN npm install -g openclaw@${OPENCLAW_VERSION} --no-audit --no-fund \
    && npm cache clean --force

# Copy health check script
COPY --chown=openclaw:openclaw scripts/healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x /usr/local/bin/healthcheck

# Copy enhanced entrypoint script (v2 with Key Vault support)
COPY --chown=openclaw:openclaw scripts/entrypoint-v2.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Set working directory
WORKDIR /data/workspace

# NOTE: Run as root so entrypoint can fix directory ownership/permissions
# The entrypoint will switch to the 'openclaw' non-root user after setup
# This is safe because dumb-init handles signal forwarding

# Expose gateway port
EXPOSE 18789

# Health check configuration
# Azure Container Apps uses HTTP probes, but this is a fallback
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start OpenClaw gateway via entrypoint
CMD ["/usr/local/bin/entrypoint"]
