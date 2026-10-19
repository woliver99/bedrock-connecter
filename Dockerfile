# ==============================================================================
# BedrockConnect + MCXboxBroadcast Container Image
# Base: Eclipse Temurin OpenJDK 21 LTS Runtime
# ==============================================================================
FROM eclipse-temurin:21-jre

# Install runtime dependencies: curl, unzip, ca-certificates, bash, iproute2
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    bash \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Pterodactyl container user setup (compatible with standalone Docker and Pterodactyl)
RUN useradd -d /home/container -m container

# Bake supervisor and entrypoint scripts into root filesystem
COPY --chmod=755 scripts/start.sh /usr/local/bin/start.sh
COPY --chmod=755 scripts/entrypoint.sh /entrypoint.sh

# Embed default templates
COPY defaults/ /defaults/

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Minecraft Bedrock UDP default port
EXPOSE 19132/udp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["start.sh"]
