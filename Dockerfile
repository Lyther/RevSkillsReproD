# syntax=docker/dockerfile:1.7
# Pin is the multi-arch index digest for node:22-bookworm-slim (2026-08-25).
FROM node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5 AS builder

WORKDIR /src
COPY vendor/rev-skills/ ./
# Zero npm dependencies; run the upstream gate as a build proof.
RUN npm test

FROM node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5 AS runner

WORKDIR /app
COPY --from=builder --chown=node:node /src /app
USER node

HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=5 \
    CMD node validate.mjs

# Workspace keep-alive: this library is a CLI/skill pack, not an HTTP server.
CMD ["node", "--input-type=module", "-e", "setInterval(() => {}, 1 << 30)"]
