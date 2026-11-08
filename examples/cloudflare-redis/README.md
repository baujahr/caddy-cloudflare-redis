# Cloudflare DNS + Redis storage example

This standalone example combines the two plugins included in the image:

- **Cloudflare DNS:** obtains HTTPS certificates using DNS-01 challenges.
- **Redis storage:** persists certificate/private-key material and coordinates
  storage operations.

Nginx is a demonstration upstream, not another public reverse proxy. Only Caddy
publishes host ports. Redis is password-protected, persists data in an AOF-backed
named volume, and is attached only to a separate internal Docker network.
The Caddy image itself does not include a Redis server.

## Prerequisites

- Docker with Docker Compose 2.24 or newer and free host ports 80 and 443.
- A real domain whose authoritative DNS is managed by Cloudflare.
- A Cloudflare API token scoped to that zone with `Zone.Zone:Read` and
  `Zone.DNS:Edit`, as described by the
  [Cloudflare provider](https://github.com/caddy-dns/cloudflare/tree/v0.2.4#authenticating).
- A hostname that clients resolve to a reachable address of your Caddy host.
  This can be public or private, including a Tailscale address; DNS-01 does not
  itself make the host reachable.

## Start

Clone the repository and enter this example's directory, or download its files
into an otherwise empty directory:

```sh
mkdir caddy-cloudflare-redis-example
cd caddy-cloudflare-redis-example
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-redis/compose.yml
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-redis/Caddyfile
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-redis/.env.example
cp .env.example .env
```

Edit `.env`: replace the domain, API token and Redis password. Generate a random
Redis password, for example with `openssl rand -hex 32`. Do not commit `.env`.
The Compose file explicitly passes the required variables to each service;
the file's presence alone would not put every value into every container.

```sh
# Check Compose interpolation without printing the resolved secrets.
docker compose config --quiet

# Redis must be healthy before Caddy validation: the storage plugin sends PING.
docker compose up -d --wait redis
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

docker compose up -d
docker compose logs --tail=100 caddy
```

Once certificate issuance succeeds, open `https://YOUR_DOMAIN`. You should see
the Nginx welcome page through Caddy. Config validation does not prove the
Cloudflare credentials work or that a public certificate has been issued;
check the running Caddy logs and the certificate served to your browser.
Avoid repeated issuance attempts while debugging; Caddy documents using an
[ACME staging endpoint](https://caddyserver.com/docs/automatic-https#testing)
to avoid production rate limits.

## Adapt it

- **Your application:** replace the `app` service and change `reverse_proxy app:80`
  to its service name and container port. Do not publish the application port
  just for Caddy to reach it.
- **Cloudflare without Redis:** remove the global `storage redis` block, Redis
  dependency, password variable and Redis service/network from this example.
  Caddy then uses local certificate storage in its persistent data volume.
- **Redis without Cloudflare:** retain the storage block and remove the `tls`
  block. A real public hostname then uses Caddy's usual HTTPS challenges,
  whose reachability requirements differ from DNS-01.
- **Existing Redis:** replace `redis:6379`, remove the bundled service and
  dependency, and configure credentials, networking and TLS for your server.
  See the [Redis plugin's configuration reference](https://github.com/pberkel/caddy-storage-redis/tree/v1.9.0#configuration).

Independent copies use project-scoped volume names, but published host ports
can still conflict. This is a single-Redis example, not a highly available
Redis deployment.

## Operations and security

For Caddyfile-only changes, validate and reload:

```sh
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

After changing Caddy's environment, recreate Caddy instead of just reloading.
If rotating the Redis password, update both Redis and Caddy and coordinate their
recreation; an existing Redis process does not adopt a changed `.env` file.
Keep all mounted Caddyfile edits in the existing file where possible; if an
editor replaces the file rather than modifying it in place, recreate Caddy
so its bind mount sees the replacement.

Back up Redis storage: it contains sensitive certificate/private-key material,
not just disposable cache data. The local Caddy data volume is not a second
copy of Redis-managed certificate storage. Switching an existing deployment
to this example does not migrate its certificates automatically.

Passwords and tokens in environment/configuration are visible to operators
with Docker access; this is not a secrets-manager integration. Redis has no
published port, but production deployments still need appropriate host/network
controls and backups. Do not publish unredacted `docker compose config` output.
Do not use `docker compose down -v` unless you intend to delete the example's
persistent volumes.
