# ---- BUILD STAGE ----
FROM golang:1.27.3-alpine AS builder

# The renovate comments tell Renovate where to find new versions.
# renovate: datasource=github-releases depName=caddyserver/caddy
ARG CADDY_VERSION=v2.11.9
# renovate: datasource=github-releases depName=caddyserver/xcaddy
ARG XCADDY_VERSION=v0.4.7
# renovate: datasource=go depName=github.com/caddy-dns/cloudflare
ARG CLOUDFLARE_DNS_VERSION=v0.2.4
# renovate: datasource=go depName=github.com/pberkel/caddy-storage-redis
ARG REDIS_STORAGE_VERSION=v1.9.0
# Newer than the version Caddy ships. Remove the --replace line once Caddy requires
# this version or newer. The build workflow fails if the replace would downgrade it.
# renovate: datasource=go depName=github.com/quic-go/quic-go
ARG QUIC_GO_VERSION=v0.64.1

RUN apk add --no-cache git

WORKDIR /src

RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION} && \
    xcaddy build ${CADDY_VERSION} \
        --output /usr/bin/caddy \
        --with github.com/caddy-dns/cloudflare@${CLOUDFLARE_DNS_VERSION} \
        --with github.com/pberkel/caddy-storage-redis@${REDIS_STORAGE_VERSION} \
        --replace github.com/quic-go/quic-go=github.com/quic-go/quic-go@${QUIC_GO_VERSION}

# ---- RUNTIME STAGE ----
# Alpine is kept on purpose: it provides sh, nc, timeout and ip for local
# startup and health commands, and curl is installed for health checks.
FROM alpine:3.24 AS runtime

RUN apk add --no-cache ca-certificates curl tzdata && \
    mkdir -p /config /data /srv /etc/caddy /usr/share/caddy && \
    chown 65532:65532 /config /data && \
    chmod 1777 /config /data

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Lets the image start on its own. Mount your own Caddyfile over this one.
COPY default/Caddyfile /etc/caddy/Caddyfile
COPY default/index.html /usr/share/caddy/index.html

ENV XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data

EXPOSE 80 443 443/udp 2019

WORKDIR /srv

LABEL org.opencontainers.image.source="https://github.com/baujahr/caddy-cloudflare-redis"

# Override with `user:` in compose if needed. /config and /data are mode 1777
# so new volumes work with any user. Caddy keeps its own files private.
USER 65532:65532

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
