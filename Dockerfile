# ==============================================================================
# BedrockConnect + MCXboxBroadcast Container Image
# Base: Eclipse Temurin OpenJDK 21 LTS Runtime
# ==============================================================================
FROM eclipse-temurin:21-jre

# Install runtime dependencies: curl, unzip, ca-certificates, bash
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Pterodactyl container user setup (compatible with standalone Docker and Pterodactyl)
RUN useradd -d /home/container -m container

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Copy startup supervisor and configuration defaults
COPY --chown=container:container scripts/start.sh /home/container/start.sh
COPY --chown=container:container defaults/ /home/container/defaults/

RUN chmod +x /home/container/start.sh

# Minecraft Bedrock UDP default port
EXPOSE 19132/udp

# Default command
CMD ["/bin/bash", "/home/container/start.sh"]
