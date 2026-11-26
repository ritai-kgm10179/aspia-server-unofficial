# syntax=docker/dockerfile:1.7

ARG ASPIA_VERSION=3.4.3

# ==============================================================================
# 階段 1：下載並驗證官方 Aspia v3 Debian (.deb) 安裝套件
# ==============================================================================
FROM debian:13-slim AS fetcher

ARG ASPIA_VERSION
ARG ASPIA_ROUTER_DEB_URL=""
ARG ASPIA_RELAY_DEB_URL=""

ENV DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /downloads

RUN --mount=type=secret,id=github_token \
    set -eu; \
    router_url="${ASPIA_ROUTER_DEB_URL}"; \
    relay_url="${ASPIA_RELAY_DEB_URL}"; \
    if [ -z "$router_url" ] || [ -z "$relay_url" ]; then \
      auth_header=""; \
      if [ -s /run/secrets/github_token ]; then \
        token="$(tr -d '\r\n' < /run/secrets/github_token)"; \
        auth_header="Authorization: Bearer ${token}"; \
      fi; \
      if [ -n "$auth_header" ]; then \
        curl -fsSL -H "Accept: application/vnd.github+json" -H "$auth_header" \
          "https://api.github.com/repos/dchapyshev/aspia/releases?per_page=30" -o /tmp/releases.json; \
      else \
        curl -fsSL -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/dchapyshev/aspia/releases?per_page=30" -o /tmp/releases.json; \
      fi; \
      if [ "$ASPIA_VERSION" = "latest" ]; then \
        jq -e '[ .[] | select((.draft | not) and (.prerelease | not) and (.tag_name | test("^v?3\\."))) | select(any(.assets[]; .name | test("^aspia-router.*(x86_64|amd64).*\\.deb$"))) | select(any(.assets[]; .name | test("^aspia-relay.*(x86_64|amd64).*\\.deb$"))) ][0]' /tmp/releases.json > /tmp/release.json; \
      else \
        jq -e --arg ver "$ASPIA_VERSION" '[ .[] | select(.tag_name == ("v" + $ver) or .tag_name == $ver) ][0]' /tmp/releases.json > /tmp/release.json; \
      fi; \
      if [ -z "$router_url" ]; then \
        router_url="$(jq -er '[.assets[] | select(.name | test("^aspia-router.*(x86_64|amd64).*\\.deb$"))][0].browser_download_url' /tmp/release.json)"; \
      fi; \
      if [ -z "$relay_url" ]; then \
        relay_url="$(jq -er '[.assets[] | select(.name | test("^aspia-relay.*(x86_64|amd64).*\\.deb$"))][0].browser_download_url' /tmp/release.json)"; \
      fi; \
      rm -f /tmp/releases.json /tmp/release.json; \
    fi; \
    curl -fsSL --retry 3 --retry-delay 2 "$router_url" -o /downloads/aspia-router.deb; \
    curl -fsSL --retry 3 --retry-delay 2 "$relay_url" -o /downloads/aspia-relay.deb; \
    dpkg-deb --info /downloads/aspia-router.deb >/dev/null; \
    dpkg-deb --info /downloads/aspia-relay.deb >/dev/null

# ==============================================================================
# 階段 2：共用的最小化 Debian 13 (Trixie) 執行時期基底映像檔
# ==============================================================================
FROM debian:13-slim AS base-runtime

ARG ASPIA_UID=1000
ARG ASPIA_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    ASPIA_LOG_LEVEL=1 \
    ASPIA_LOG_TO_STDOUT=1 \
    ASPIA_LOG_TO_FILE=0

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      tzdata \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && (getent group "${ASPIA_GID}" >/dev/null || groupadd -g "${ASPIA_GID}" aspia) \
    && (id -u "${ASPIA_UID}" >/dev/null 2>&1 || useradd -u "${ASPIA_UID}" -g "${ASPIA_GID}" -d /var/lib/aspia -s /bin/sh -M aspia) \
    && mkdir -p /etc/aspia /var/lib/aspia /var/log/aspia /run/aspia-keys /usr/local/lib/aspia \
    && chown -R "${ASPIA_UID}:${ASPIA_GID}" /etc/aspia /var/lib/aspia /var/log/aspia /run/aspia-keys

COPY --chmod=0644 scripts/lib-ini.sh /usr/local/lib/aspia/lib-ini.sh
COPY --chmod=0755 scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

# ==============================================================================
# 階段 3a：Aspia Router v3 映像檔
# ==============================================================================
FROM base-runtime AS router

ARG ASPIA_VERSION

LABEL org.opencontainers.image.title="Aspia Router v3" \
      org.opencontainers.image.description="Unofficial hardened Debian 13 slim container for Aspia v3 Router" \
      org.opencontainers.image.version="${ASPIA_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.documentation="https://aspia.org/docs/"

# hadolint ignore=DL3008
RUN --mount=type=bind,from=fetcher,source=/downloads,target=/mnt/downloads \
    apt-get update && apt-get install -y --no-install-recommends /mnt/downloads/aspia-router.deb \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && command -v aspia_router

COPY --chmod=0755 scripts/entrypoint-router.sh /usr/local/bin/entrypoint-router.sh

USER 1000:1000

EXPOSE 8061/tcp 8062/tcp 8063/tcp 8065/udp

VOLUME ["/etc/aspia", "/var/lib/aspia"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh", "router"]

ENTRYPOINT ["/usr/local/bin/entrypoint-router.sh"]

# ==============================================================================
# 階段 3b：Aspia Relay v3 映像檔
# ==============================================================================
FROM base-runtime AS relay

ARG ASPIA_VERSION

LABEL org.opencontainers.image.title="Aspia Relay v3" \
      org.opencontainers.image.description="Unofficial hardened Debian 13 slim container for Aspia v3 Relay" \
      org.opencontainers.image.version="${ASPIA_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.documentation="https://aspia.org/docs/"

# hadolint ignore=DL3008
RUN --mount=type=bind,from=fetcher,source=/downloads,target=/mnt/downloads \
    apt-get update && apt-get install -y --no-install-recommends /mnt/downloads/aspia-relay.deb \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && command -v aspia_relay

COPY --chmod=0755 scripts/entrypoint-relay.sh /usr/local/bin/entrypoint-relay.sh

USER 1000:1000

EXPOSE 8070/tcp

VOLUME ["/etc/aspia"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh", "relay"]

ENTRYPOINT ["/usr/local/bin/entrypoint-relay.sh"]
