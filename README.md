# caddy-cloudflare-redis

An unofficial [Caddy](https://caddyserver.com/) image with these plugins:

- [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [pberkel/caddy-storage-redis](https://github.com/pberkel/caddy-storage-redis)

The image is built by GitHub Actions and published to GHCR for `linux/amd64` and `linux/arm64`. It runs as `65532:65532` and works with a read-only root filesystem and all capabilities dropped.

## Use

Either way, Caddy starts with a built-in default page on port 80.

### Docker Compose

You need Docker Compose 2.24 or newer.

```sh
curl -O https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/compose.yml
docker compose up -d
```

### docker run

```sh
docker run -d --name caddy --restart always \
  -p 80:80 -p 443:443 -p 443:443/udp \
  --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp \
  -v caddy-config:/config -v caddy-data:/data \
  ghcr.io/baujahr/caddy-cloudflare-redis:latest
```

To use your own config, add these before the image name:

```sh
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" \
  --env-file .env \
```

The rest of this page uses Compose, but each setting has a `docker run` equivalent, such as `--user` or `--network host`.

## Your own config

Put anything specific to your setup in a `compose.override.yml` next to `compose.yml`. Compose merges it automatically, and git ignores it.

To serve your own sites, mount your Caddyfile:

```yaml
services:
  caddy:
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
```

Keep secrets in a `.env` file next to `compose.yml`. Caddy can read them, for example as `{env.CLOUDFLARE_API_TOKEN}`. See [`.env.example`](.env.example).

### Host networking

```yaml
services:
  caddy:
    network_mode: host
    ports: !reset []
```

With all capabilities dropped, Caddy can only bind ports 80 and 443 on the host network if the host allows it:

```sh
sysctl net.ipv4.ip_unprivileged_port_start=80
```

Add this to `/etc/sysctl.d/` to keep it after a reboot.

### Health check

The image has no built-in health check, because that depends on your Caddyfile. To add one:

```yaml
services:
  caddy:
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://127.0.0.1:3000/ || exit 1"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 30s
```

This needs a matching site in your Caddyfile:

```caddyfile
http://127.0.0.1:3000 {
	bind 127.0.0.1
	respond / 200
}
```

The image is Alpine-based, so `sh`, `nc`, `timeout`, `ip` and `curl` are available for startup and health commands.

## Running as another user

Set `user:` in your override:

```yaml
services:
  caddy:
    user: "99:100"
```

New named volumes work with any user, because `/config` and `/data` are mode `1777` in the image. Caddy keeps its own files private to the user it runs as.

To change the user on volumes that already have data, change the owner first. Otherwise Caddy can stop with a `permission denied` error.

```sh
docker compose down
docker run --rm --user 0 -v caddy-config:/c -v caddy-data:/d \
  --entrypoint chown ghcr.io/baujahr/caddy-cloudflare-redis:latest -R 99:100 /c /d
```

If you use bind mounts instead of named volumes, the host folders must be writable by that user.

## Tags

| Tag | Meaning |
|---|---|
| `latest` | Newest build. |
| `2.11.9-r12` | One specific build, where `12` is the workflow run number. It doesn't move. |

Tags ending in `-amd64` or `-arm64` are the single-architecture parts of a build. Use the tags above instead.

To stay on a build, set that tag as `image:` in your override.

## Updates

The image is rebuilt only when `Dockerfile` or `default/` changes, or when the workflow is run by hand. Renovate proposes new versions of Caddy, the plugins and the base images. To update a host, run `docker compose pull && docker compose up -d`, or use a tool like Watchtower that follows `latest`.

## License

The files in this repo are [MIT](LICENSE) licensed. Caddy and the included plugins keep their own licenses.
