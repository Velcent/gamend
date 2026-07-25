---
icon: hero-cloud-arrow-up
---

# Deployment

Deploy your own game server instance using the starter repository. The quickest path is Docker Compose — clone, configure, and run. If you want a full Elixir host app that you can edit directly, see the Elixir App Starter guide below.

Two supported starting paths

- Docker starter: fastest path to running a server with minimal code changes
- Elixir app starter: best path when you want to own the host app, routes, branding, and runtime policy in code

## What each project owns

The repository is split by responsibility. Treat host as the runtime shell you customize, and core/web as reusable packages that you update from upstream.

| Project | Owns | Typical changes |
|---|---|---|
| game_server_core | Shared domain logic, Ecto schemas, contexts, and upstream migrations | New shared features, shared data model changes, reusable business rules |
| game_server_web | Shared controllers, LiveViews, channels, components, and shared frontend source | Reusable API/UI behavior that multiple hosts should inherit |
| game_server_host | The runnable app: router, endpoint boot, supervision tree, env/config, branding, docs, startup scripts, and host-only migrations | Routes you add or remove, deployment policy, assets, host-owned pages, integrations, and data that only your host needs |

## Host-only migrations

Put upstream shared schema changes in game_server_core, but put host-specific tables or columns in priv/repo/migrations at the repository root. The host migration command runs both core and host paths together.

```bash
mix ecto.gen.migration add_custom_host_table

mix ecto.migrate
```

Migration versions from core and host are sorted together, so give host migrations a normal timestamp and keep host-only schema/modules in the host project unless you intentionally want to upstream them into core.

## Clone the Docker starter repository

The starter repo contains a pre-configured Docker Compose setup with the game server, PostgreSQL, and optional Redis for caching.

```bash
git clone https://github.com/appsinacup/gamend_starter.git
cd gamend_starter
```

## Configure environment variables

Copy the example environment file and edit it to set your secrets and configuration.

```bash
cp .env.example .env
```

Key variables to set:

| Variable | Description |
|---|---|
| SECRET_KEY_BASE | 64-byte hex secret for session signing. Generate with: mix phx.gen.secret |
| DATABASE_URL | PostgreSQL connection string (pre-configured for the Docker Compose DB) |
| PHX_HOST | Your public hostname (e.g. play.example.com) |
| GUARDIAN_SECRET_KEY | Secret for signing JWT API tokens |

See the .env.example file for the full list of available environment variables including OAuth providers, email, rate limiting, and more.

## Start the server

Start everything with Docker Compose:

```bash
docker compose up -d
```

The server will be available at http://localhost:4000 by default. Database migrations run automatically on startup.

## Verify the deployment

Check that the server is running:

```bash
curl http://localhost:4000/api/v1/health

docker compose logs -f app
```

## Production recommendations

- Enable HTTPS with automatic certificate renewal (see below)
- Set PHX_HOST to your actual domain
- Configure OAuth providers for social login (see provider guides above)
- Enable email delivery via SMTP for password resets and notifications
- Set up Redis for distributed caching when running multiple instances (see Scaling guide)
- Review rate limiting settings for your expected traffic

## Data retention

A sweep runs every 6 hours and prunes tables that would otherwise grow forever. Each window is one env var; 0 keeps that class forever. See the last run and its per-class counts under Admin -> System, where you can also run a sweep on demand.

| Variable | Default | Prunes |
|---|---|---|
| RETENTION_ABANDONED_LOBBY_MINUTES | 15 | Lobbies nobody in them has been seen in for the window, so a reconnect always saves one. Ending a match is not a reason to delete: a game that ends one deletes its own lobby. Raise this if your game keeps rooms open between sessions. |
| RETENTION_INVITES_DAYS | 30 | Resolved group/party invites and join requests. Pending ones are never pruned. |
| RETENTION_MATCHMAKING_TICKETS_HOURS | 24 | Matchmaking tickets, in any status. |
| RETENTION_CHAT_DAYS | 0 | Chat messages. |
| RETENTION_NOTIFICATIONS_DAYS | 0 | Notifications. |
| RETENTION_PAYMENT_EVENTS_DAYS | 0 | Provider webhook events. Purchases and entitlements are never pruned. |
| RETENTION_LOBBY_SNAPSHOTS_DAYS | 30 | Lobby snapshots, events and blobs. Runs flagged anomalous keep RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS (90) instead. |
| RETENTION_PUSH_TOKENS_DAYS | 270 | Push tokens untouched this long: dead installs. |
| RETENTION_TOURNAMENTS_DAYS | 0 | Finished tournaments and their bracket rows. Opt-in. |
| RETENTION_LEDGER_DAYS | 0 | Wallet and inventory ledgers. Opt-in: this is the audit trail behind every balance. |

Expired sessions and magic-link tokens are always pruned on their own validity, and are not configurable.

## HTTPS

Gamend terminates TLS itself through Bandit — no nginx or reverse proxy. Point
it at a certificate and it serves HTTPS on 443, keeping HTTP on 4000 for ACME
challenges. Erlang's `:ssl` re-reads the files from disk, so a renewal takes
effect **without a restart**.

| Variable | Purpose |
|---|---|
| `SSL_CERTFILE` | Path to `fullchain.pem` (certificate + CA chain) |
| `SSL_KEYFILE` | Path to `privkey.pem` |
| `FORCE_SSL` | `true` redirects HTTP to HTTPS and enables HSTS |
| `ACME_WEBROOT` | Directory the ACME challenge is served from |

Get a certificate with the server already running on HTTP, so certbot can
validate over the webroot:

```bash
sudo mkdir -p /var/www/acme
sudo certbot certonly --webroot --webroot-path /var/www/acme \
  --email admin@example.com --agree-tos --no-eff-email -d play.example.com
```

Then point the server at what certbot wrote and restart:

```bash
PHX_HOST=play.example.com
SSL_CERTFILE=/etc/letsencrypt/live/play.example.com/fullchain.pem
SSL_KEYFILE=/etc/letsencrypt/live/play.example.com/privkey.pem
FORCE_SSL=true
ACME_WEBROOT=/var/www/acme
```

Certbot installs its own renewal timer, so there is nothing further to
schedule; `sudo certbot renew --dry-run` confirms it works.

### Docker setup

When running in Docker, mount the certificate directory and ACME challenge directory as volumes. Add these to your docker-compose.yml:

```yaml
# docker-compose.yml — add HTTPS support
services:
  app:
    ports:
      - "4000:4000"
      - "443:443"
    environment:
      PHX_HOST: play.example.com
      SSL_CERTFILE: /etc/letsencrypt/live/play.example.com/fullchain.pem
      SSL_KEYFILE: /etc/letsencrypt/live/play.example.com/privkey.pem
      FORCE_SSL: "true"
      ACME_WEBROOT: /var/www/acme
    volumes:
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/acme:ro
```

Run certbot on the host machine (not inside Docker). It writes to ./certbot/conf/ and ./certbot/www/ which are mounted into the container:

```bash
# 1. Create cert directories
mkdir -p certbot/conf certbot/www

# 2. Start the server (HTTP only — certs don't exist yet)
docker compose up -d

# 3. Get your first certificate (run on the HOST)
sudo certbot certonly \
  --webroot --webroot-path ./certbot/www \
  --email admin@example.com --agree-tos \
  -d play.example.com \
  --config-dir ./certbot/conf \
  --work-dir ./certbot/work \
  --logs-dir ./certbot/logs

# 4. Restart to enable HTTPS (cert files now exist)
docker compose up -d

# 5. Set up auto-renewal cron on the host (every 12 hours)
(crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --config-dir $(pwd)/certbot/conf --work-dir $(pwd)/certbot/work --logs-dir $(pwd)/certbot/logs --quiet") | crontab -
```

Renewed certs are picked up automatically — no container restart needed.

### Environment variables reference

| Variable | Description | Default |
|---|---|---|
| SSL_CERTFILE | Path to fullchain.pem (certificate + CA chain) | — |
| SSL_KEYFILE | Path to privkey.pem | — |
| HTTPS_PORT | Port for HTTPS listener | 443 |
| FORCE_SSL | Redirect HTTP → HTTPS and enable HSTS | true when SSL_CERTFILE is set |
| ACME_WEBROOT | Webroot directory for Let's Encrypt HTTP-01 challenges (same as certbot --webroot-path) | /var/www/acme |

Port 443 access

Binding to port 443 requires root access or Linux capabilities. In Docker this works by default. On bare metal, use: sudo setcap 'cap_net_bind_service=+ep' $(which beam.smp) — or use iptables to redirect port 443 to a higher port.
