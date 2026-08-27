# syntax=docker/dockerfile:1
#
# Multi-stage build on Chainguard's Wolfi Node images — continuously rebuilt to
# zero known CVEs, minimal (no shell / package managers in the runtime), and
# non-root by default. This is the secure base every service on the paved road
# shares; keep the shape (multi-stage, lockfile install, non-root, exec-form CMD)
# even if the app grows.
#
# Pinned by digest (Chainguard's free tier is :latest-only) for reproducibility
# and to satisfy Hadolint. Refresh with:
#   docker buildx imagetools inspect cgr.dev/chainguard/node:latest
#   docker buildx imagetools inspect cgr.dev/chainguard/node:latest-dev

# --- build: install production deps from the committed lockfile (build once).
FROM cgr.dev/chainguard/node@sha256:f33e85c75e96cac9c0cc934c630164b78a1600fc30a519afa26e9204352e34af AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# --- runtime: minimal Chainguard node, non-root (uid 65532), no shell / package managers.
FROM cgr.dev/chainguard/node@sha256:7740ce8ef7cce4b0892e85813cbb39abe48c56bd48290cb18b9ea721480263f3
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY src ./src
USER 65532
EXPOSE 3000
# The Chainguard node image's ENTRYPOINT is `node`; CMD is the script it runs.
CMD ["/app/src/server.js"]
