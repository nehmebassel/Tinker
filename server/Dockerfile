# tinker-api: Node 22 server + headless Godot (same build as the game) for server-side replay.
# Build context is the REPO ROOT:  docker build -f server/Dockerfile .
FROM node:22-bookworm-slim

ARG GODOT_VERSION=4.5.1-stable
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /opt/godot && mv /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot && rm -rf /tmp/godot.zip /opt/godot \
 && apt-get purge -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# The game: scripts, parts, levels. game/levels is a symlink in the repo; copy real files instead.
COPY game/ /app/game/
RUN rm -f /app/game/levels
COPY levels/ /app/game/levels/
# Import once at build time so class_name scripts resolve when the server spawns Godot.
RUN HOME=/tmp godot --headless --path /app/game --import >/dev/null 2>&1 || true \
 && test -f /app/game/.godot/global_script_class_cache.cfg

RUN chown -R node:node /app/game
COPY server/package.json server/package-lock.json /app/server/
RUN cd /app/server && npm ci --omit=dev
COPY server/src/ /app/server/src/
COPY server/static/ /app/server/static/

# Player-facing builds, exported by tools/build_clients.sh before the image is built.
COPY build/web/ /app/web/
COPY build/download/ /app/download/

ENV NODE_ENV=production GAME_DIR=/app/game GODOT_BIN=/usr/local/bin/godot HOME=/tmp WEB_DIR=/app/web DOWNLOAD_DIR=/app/download
USER node
WORKDIR /app/server
CMD ["node", "src/index.js"]
