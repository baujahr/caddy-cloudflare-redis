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
| `latest` | A validated build promoted while its source revision is the current `main` head. |
| `2.11.9-r12-a2` | An attempt-specific build: workflow run `12`, attempt `2`. |

Tags ending in `-amd64` or `-arm64` are the single-architecture parts of a build. Use the tags above instead.

To select a build, set its attempt-specific tag as `image:` in your override.
These tags distinguish reruns, but they are not registry-enforced immutable tags.
For an exact artifact, pin the multi-architecture manifest digest instead:
`ghcr.io/baujahr/caddy-cloudflare-redis@sha256:<manifest-digest>`.
Older run-number-only tags should not be treated as immutable either.

### Validation and publication

Every pull request targeting `main` runs Compose validation, release-policy tests,
and the AMD64/ARM64 builds and smoke tests. PR jobs have read-only repository
permissions and never log in to GHCR or publish images.

Relevant pushes to `main` and manual dispatches on `main` can publish. Tested
images pass to a separate package-write job as artifacts named by run ID,
attempt and architecture. Publication requires both architectures from the same
attempt. For a publication retry, choose **Re-run all jobs**, not just failed
jobs or the publish job; missing current-attempt artifacts cause publication to
fail rather than reuse an older attempt.

Publication is serialized, but serialization does not imply revision ordering.
Historical runs can publish their attempt-specific tags; only a revision matching
the freshly queried remote `main` head can promote `latest`. A branch advance,
including a documentation-only commit, can therefore skip promotion. The head
check is immediately before promotion, not an atomic transaction with GitHub:
a new push can still occur between the check and registry update.

This policy applies to runs using the updated workflow. Historical runs using
the original workflow still contain its unconditional `latest` publication;
do not rerun them. Adopting this workflow does not retroactively change those
definitions or revoke their publishing authority.

## Updates

On `main`, builds run when `Dockerfile`, `default/`, `.dockerignore`, `.github/`,
`compose*.yml` or `.env.example` changes, or when dispatched manually. PR
validation has no path filter. Renovate proposes new versions of Caddy, the
plugins and the base images. To update a host, run
`docker compose pull && docker compose up -d`, or use a tool like Watchtower that
follows `latest`.

## License

The files in this repo are [MIT](LICENSE) licensed. Caddy and the included plugins keep their own licenses.
