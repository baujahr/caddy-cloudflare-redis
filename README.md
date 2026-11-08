# caddy-cloudflare-redis

An unofficial container image of [Caddy](https://github.com/caddyserver/caddy),
the web server with automatic HTTPS, with the
[Cloudflare DNS](https://github.com/caddy-dns/cloudflare) and
[Redis storage](https://github.com/pberkel/caddy-storage-redis) plugins included.
See the [Caddy documentation](https://caddyserver.com/docs/) for general
configuration.

Use this image as a standalone reverse proxy for several applications, or add
it as a service in an application's existing Compose project. The plugins are
installed, not enabled automatically: you do not need Cloudflare or Redis to
run the image. Redis itself is not bundled.

The image is published to GHCR for `linux/amd64` and `linux/arm64`. It runs as
`65532:65532` and supports a read-only root filesystem with all capabilities
dropped. See [versions and build choices](#versions-and-build-choices) for the
pinned components and the personal quic-go/Tailscale compatibility preference.

## Quick start

You need Docker with Docker Compose 2.24 or newer, and free host ports 80 and
443. Start in a new directory so you do not overwrite an application's existing
`compose.yml`:

```sh
mkdir caddy-proxy
cd caddy-proxy
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/compose.yml
docker compose up -d
curl http://localhost/
```

You should see the built-in "Caddy is running" page. This is only an HTTP
smoke test: the [default Caddyfile](default/Caddyfile) does not configure a real
site, HTTPS, Cloudflare or Redis, even though the Compose file publishes ports
80 and 443.

The supplied [compose.yml](compose.yml) is a standalone deployment with fixed
container and volume names. Do not start independent copies on the same Docker
host without changing those names and any conflicting published ports. For an
existing application project, add a Caddy service to that project's Compose
file instead; use project-scoped names unless sharing is intentional.

## Your first reverse proxy

In the quick-start directory, create a file named `Caddyfile`:

```caddyfile
:80 {
	reverse_proxy app:80
}
```

Create `compose.override.yml` beside `compose.yml`:

```yaml
services:
  caddy:
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
  app:
    image: nginx:alpine
```

The `app` service is just a demonstration upstream. Validate the configuration
and start it:

```sh
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose up -d
curl http://localhost/
docker compose logs --tail=50 caddy
```

You should now see the Nginx welcome page through Caddy. Both services share the
project's default network, and `app:80` refers to the application's container
port, not a published host port. Replace `app` with your real application and
use the port it listens on. Inside Caddy's container, `localhost` means Caddy
itself, not your host or a neighboring application.

For a shared proxy serving applications in other Compose projects, connect
Caddy and the intended upstream services to a shared external Docker network.
Separate projects do not share their default networks. See
[Docker's cross-project networking example](https://docs.docker.com/compose/how-tos/networking/#connecting-multiple-compose-projects).
Do not attach databases or other private services unless Caddy needs them.

Compose loads `compose.override.yml` automatically in this workflow. Overrides
merge rather than replace every setting: port mappings can accumulate. See
[Compose merge rules](https://docs.docker.com/reference/compose-file/merge/) before
changing ports or networks.

## Enable Cloudflare DNS challenges

You need a domain whose authoritative DNS is managed by Cloudflare and a
zone-scoped API token with `Zone.Zone:Read` and `Zone.DNS:Edit` permissions.
Use an API token, not the global API key; see the
[provider's authentication instructions](https://github.com/caddy-dns/cloudflare/tree/v0.2.4#authenticating).

In the quick-start directory, create `.env`:

```dotenv
CLOUDFLARE_API_TOKEN=replace-with-your-zone-scoped-api-token
```

The supplied Compose file passes this file to Caddy. Replace the HTTP-only
`Caddyfile` with:

```caddyfile
app.example.com {
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
	}
	reverse_proxy app:80
}
```

Replace `app.example.com` with your own hostname. Configure DNS so clients can
resolve that hostname to an address from which they can reach Caddy. DNS-01
certificate validation does not require publicly exposing port 80, but it also
does not create a route to a private or Tailscale-only server.

Validate, then recreate Caddy to load the new environment:

```sh
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose up -d --force-recreate caddy
docker compose logs --tail=50 caddy
```

Visit `https://app.example.com` once issuance succeeds. The token enables DNS
challenges; it does not configure Cloudflare proxying, Tunnels or Tailscale.
Redis is still optional: without a Redis storage block, Caddy uses its normal
local storage in the persistent data volume.

## Enable Redis storage, with Cloudflare

The complete [Cloudflare + Redis example](examples/cloudflare-redis/) includes
a Caddyfile, Compose file and environment template. It runs Caddy, an Nginx
demonstration upstream and a password-protected Redis instance with persistent
storage. Redis has no published host port and uses a separate internal network.

To configure an existing Redis service instead, add this global options block
at the very beginning of your Caddyfile, before the site blocks:

```caddyfile
{
	storage redis {
		address redis:6379
		password "{$REDIS_PASSWORD}"
		key_prefix caddy
	}
}
```

Set `REDIS_PASSWORD` in the environment passed to Caddy and make sure
`redis:6379` is reachable from Caddy's network. Keep your existing Cloudflare
`tls` block in the site below it. If using a remote Redis server, configure its
authentication and TLS as appropriate; the
[Redis plugin documentation](https://github.com/pberkel/caddy-storage-redis/tree/v1.9.0#configuration)
describes the available options.

Redis stores certificate/private-key material and coordination data, not HTTP
response caches or your application database. Protect and back up that data.
The plugin checks Redis connectivity during startup, reload and validation, so
start Redis before running `caddy validate`. Switching storage does not
automatically migrate an existing local certificate store.

## Everyday commands

Run these from the directory containing your deployment's Compose file:

```sh
# Validate before applying configuration changes.
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Apply an edited Caddyfile without restarting the container.
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

# Inspect startup, certificate and upstream errors.
docker compose logs --tail=100 caddy

# Pull an updated image and recreate services as needed.
docker compose pull
docker compose up -d
```

After changing `.env` or Compose settings, recreate Caddy with
`docker compose up -d --force-recreate caddy`; a Caddyfile reload alone does not
refresh container environment variables. Never commit real tokens or passwords.
Avoid sharing unredacted configuration output or logs containing secrets.

## docker run alternative

To start the same HTTP welcome page without Compose:

```sh
docker run -d --name caddy --restart always \
  -p 80:80 -p 443:443 -p 443:443/udp \
  --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp \
  -v caddy-config:/config -v caddy-data:/data \
  ghcr.io/baujahr/caddy-cloudflare-redis:latest
```

For your own configuration, create `Caddyfile` and `.env` first, then add these
options before the image name:

```sh
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" \
  --env-file .env \
```

A proxy upstream in another container also needs a shared network, for example
via `--network`. The rest of this README uses Compose.

## Versions and build choices

These are the versions currently selected in the [Dockerfile](Dockerfile), not
a promise about older image tags:

| Component | Version | Purpose |
|---|---|---|
| [Caddy](https://github.com/caddyserver/caddy) | `v2.11.9` | Web server and reverse proxy |
| [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare) | `v0.2.4` | Cloudflare DNS challenges for HTTPS certificates |
| [pberkel/caddy-storage-redis](https://github.com/pberkel/caddy-storage-redis) | `v1.9.0` | Redis-backed certificate storage and coordination |
| [quic-go](https://github.com/quic-go/quic-go) | `v0.64.1` | QUIC transport used by HTTP/3; explicitly overridden |
| [xcaddy](https://github.com/caddyserver/xcaddy) | `v0.4.7` | Build tool, not a runtime service |

Inspect the actual Caddy version, installed modules or Go build dependencies
in an image you have pulled:

```sh
docker run --rm ghcr.io/baujahr/caddy-cloudflare-redis:latest caddy version
docker run --rm ghcr.io/baujahr/caddy-cloudflare-redis:latest caddy list-modules --versions
docker run --rm ghcr.io/baujahr/caddy-cloudflare-redis:latest caddy build-info
```

### Why a newer quic-go?

This is a personal build preference: HTTP/3 over Tailscale did not work in the
maintainer's earlier setup, which motivated using a newer quic-go version than
the one selected by this Caddy release. The [Dockerfile](Dockerfile) explicitly
replaces that dependency with `v0.64.1`; this is not an upstream Caddy
recommendation or a claim that all Tailscale users need it.

No special Tailscale configuration is enabled in the image. HTTP/3 still depends
on the client and network, including UDP connectivity to Caddy; the override
does not guarantee HTTP/3 will work on every tailnet. The build checks that the
replacement does not downgrade Caddy's selected quic-go dependency.

## Advanced configuration

### Host networking

On a Linux host, this override selects host networking instead of bridge
networking:

```yaml
services:
  caddy:
    network_mode: host
    ports: !reset []
```

With all capabilities dropped, binding low ports depends on the host's policy.
For a host that does not already permit unprivileged binding to ports 80 and
443, an administrator can change it:

```sh
sudo sysctl net.ipv4.ip_unprivileged_port_start=80
```

To persist that policy, add `net.ipv4.ip_unprivileged_port_start=80` to a file
under `/etc/sysctl.d/`. This changes host policy, not just this container.
Host networking also removes Compose service-name discovery; adjust upstream
and Redis addresses instead of continuing to use `app` or `redis`.

### Health check

The image has no built-in health check because that depends on your Caddyfile.
An optional loopback-only HTTP endpoint avoids public HTTPS dependencies:

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

Add the matching site to your Caddyfile:

```caddyfile
http://127.0.0.1:3000 {
	bind 127.0.0.1
	respond / 200
}
```

This checks Caddy's HTTP listener, not application health or successful public
certificate issuance. The Alpine-based image includes `sh`, `nc`, `timeout`,
`ip` and `curl` for startup and health commands.

### Running as another user

Set `user:` in your override:

```yaml
services:
  caddy:
    user: "99:100"
```

New named volumes initialized from the image work with an alternate UID/GID
because `/config` and `/data` are mode `1777`. Existing Caddy files can remain
private to the user that created them; changing `user:` does not change their
ownership.

For the root standalone Compose file's fixed volume names, stop Caddy and
change ownership before switching users:

```sh
docker compose down
docker run --rm --user 0 -v caddy-config:/c -v caddy-data:/d \
  --entrypoint chown ghcr.io/baujahr/caddy-cloudflare-redis:latest -R 99:100 /c /d
docker compose up -d
```

Use the actual volume names for other projects; do not run this against volumes
owned by another deployment. Bind-mounted host folders must also be writable
by the selected UID/GID. Never use `docker compose down -v` just to change users:
it removes deployment volumes and their data.

## Tags and build updates

| Tag | Meaning |
|---|---|
| `latest` | Moving tag updated by the publishing workflow |
| `2.11.9-r12` | Caddy version plus workflow run number; a rerun can replace it |

Tags ending in `-amd64` or `-arm64` are single-architecture parts; normally use
the multi-architecture tag. Set your selected image under the service's `image:`
key. For an exact artifact, use a manifest digest rather than relying on a tag
being immutable.

The current workflow rebuilds on changes to `Dockerfile` or `default/`, or a
manual workflow run. Documentation-only changes do not rebuild the image.
Renovate proposes dependency updates. When reviewing updates, check the
[Dockerfile](Dockerfile) for the authoritative selected versions; the version
table above should be kept in sync.

## License

The files in this repo are [MIT](LICENSE) licensed. Caddy and the included
plugins keep their own licenses.
