# Cloudflare DNS + Valkey storage example

This standalone example runs Caddy as a reverse proxy for containers you
already have, using both plugins included in the image:

- **Cloudflare DNS:** obtains HTTPS certificates using DNS-01 challenges.
- **Redis storage, backed by [Valkey](https://github.com/valkey-io/valkey):**
  keeps certificates, private keys and coordination locks in Valkey. The plugin
  speaks the Redis protocol, which Valkey implements.

Only Caddy publishes host ports. Valkey is password-protected, persists data
in an append-only file on a named volume, and is attached only to a private
internal network. Your applications reach Caddy through a shared external
network named `caddy`. The Caddy image itself does not include Valkey.

## Prerequisites

- Docker with Docker Compose 2.24 or newer and free host ports 80 and 443.
- A real domain whose authoritative DNS is managed by Cloudflare.
- A Cloudflare API token scoped to that zone with `Zone.Zone:Read` and
  `Zone.DNS:Edit`, as described by the
  [Cloudflare provider](https://github.com/caddy-dns/cloudflare/tree/v0.2.4#authenticating).
- Hostnames that clients resolve to a reachable address of your Caddy host.
  This can be public or private, including a Tailscale address; DNS-01 does not
  itself make the host reachable.

## Start

Create the shared network once:

```sh
docker network create caddy
```

Download this example into an empty directory:

```sh
mkdir caddy-proxy
cd caddy-proxy
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-valkey/compose.yml
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-valkey/Caddyfile
curl -fLO https://raw.githubusercontent.com/baujahr/caddy-cloudflare-redis/main/examples/cloudflare-valkey/.env.example
cp .env.example .env
```

Edit `.env`: set the API token and a random Valkey password, for example from
`openssl rand -hex 32`. Do not commit `.env`. The Compose file passes each
required variable explicitly to the service that needs it.

Edit `Caddyfile`: replace the example hostnames and upstreams with your own,
one site block per application.

## Connect your applications

In each application's own `compose.yml`, attach the service Caddy should reach
to the `caddy` network:

```yaml
services:
  my-app:
    # ...your existing image, volumes and environment...
    container_name: my-app
    networks:
      - default # keeps access to the application's own database and services
      - caddy

networks:
  caddy:
    external: true
```

Run `docker compose up -d` in that application's directory. In the Caddyfile,
use the container name and the port the application listens on inside its
container: for a mapping such as `3000:8080`, that is `8080`. The application
no longer needs its own published host port once Caddy proxies it. Use unique
container names; generic names such as `app` or `web` can collide on a shared
network. Do not attach databases or other private services to `caddy`.

## Validate and run

```sh
# Check Compose interpolation without printing the resolved secrets.
docker compose config --quiet

# Valkey must be healthy before validation: the storage plugin connects to it.
docker compose up -d --wait valkey
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

docker compose up -d
docker compose logs --tail=100 caddy
```

Once certificate issuance succeeds, open each hostname in a browser. Config
validation does not prove the Cloudflare credentials work, that a certificate
has been issued or that the upstream containers are reachable; check the Caddy
logs. Avoid repeated issuance attempts while debugging; Caddy documents using
an [ACME staging endpoint](https://caddyserver.com/docs/automatic-https#testing)
to avoid production rate limits.

## Adapt it

- **Cloudflare without Valkey:** remove the global `storage redis` block, the
  Valkey dependency, password variable, Valkey service and `storage` network.
  Caddy then keeps certificates in its persistent data volume.
- **Valkey without Cloudflare:** remove the `acme_dns` line. A public hostname
  then uses Caddy's usual HTTP or TLS-ALPN challenges, which require clients
  on the internet to reach ports 80 or 443.
- **Existing Valkey or Redis server:** replace `valkey:6379`, remove the
  bundled service and dependency, and configure credentials, networking and
  TLS for your server. See the
  [storage plugin's configuration reference](https://github.com/pberkel/caddy-storage-redis/tree/v1.9.0#configuration).

This is a single-server example, not a highly available Valkey deployment.

## Operations and security

For Caddyfile-only changes, validate and reload:

```sh
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

After changing Caddy's environment, recreate Caddy instead of just reloading.
When rotating the Valkey password, update `.env` and recreate both Valkey and
Caddy; a running Valkey process does not reread `.env`. If your editor replaces
the Caddyfile instead of modifying it in place, recreate Caddy so its bind
mount sees the new file.

Back up the Valkey volume: it contains certificate and private-key material,
not just disposable cache data. Caddy's local data volume is not a second copy
of it. Switching an existing deployment to this example does not migrate its
certificates automatically.

Passwords and tokens in the environment and configuration are visible to
anyone with Docker access on the host; this is not a secrets-manager
integration. Do not publish unredacted `docker compose config` output. Do not
use `docker compose down -v` unless you intend to delete the example's
persistent volumes.
