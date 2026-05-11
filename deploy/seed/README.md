# TribeEco seed node

A seed node is a public TribeEco hub that other hubs use to bootstrap into the gossip mesh. Home Macs running `tribe start` connect outbound to a seed over WebSocket — no inbound ports needed on the home side, so it works behind any home router.

This directory deploys a single seed fronted by [Caddy](https://caddyserver.com) for automatic Let's Encrypt TLS. The hub is reachable at `https://$DOMAIN` and `wss://$DOMAIN/gossip`.

The default seed baked into `bin/tribe` is `wss://seed.tribeapp.wtf/gossip`. Fresh `brew install tribe` users join the global mesh automatically on first `tribe start`.

## Prerequisites

- A VPS with a public IPv4. Cheapest options:
  - **Oracle Cloud Always Free** (Mumbai / Hyderabad), 4 ARM cores + 24 GB RAM, free forever. Ubuntu 22.04 image.
  - DigitalOcean / Vultr / Lightsail $4–6/mo droplet in any region.
- A domain (or subdomain) with an **A record** pointing at the VPS public IP. Wait until `dig +short $DOMAIN` returns the IP before running setup — Caddy's ACME HTTP-01 challenge needs DNS to resolve before it can issue a cert.
- Cloud firewall / security list **open on TCP 80 and 443**. Port 4000 is _not_ exposed publicly; Caddy fronts the hub on the internal docker network.
  - **Oracle Cloud:** Networking → Virtual Cloud Networks → your VCN → Security Lists → Default Security List → Add Ingress Rules. Source `0.0.0.0/0`, protocol TCP, destination ports `80` and `443`.

## One-shot install

SSH into the VPS and run:

```bash
DOMAIN=seed.example.com bash <(curl -fsSL https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/seed/setup-seed.sh)
```

The script:

1. Installs Docker if missing.
2. Clones / updates the repo at `~/tribe-seed`.
3. Builds and starts `hub-db`, `hub`, and `caddy`.
4. Opens iptables ports 80 + 443.
5. Waits for the hub container to report healthy.
6. Curls `https://$DOMAIN/health` end-to-end and reports the result.

First boot takes ~60s while Caddy negotiates the Let's Encrypt cert. If `https://$DOMAIN/health` doesn't respond yet, tail Caddy:

```bash
docker compose -f ~/tribe-seed/deploy/seed/docker-compose.seed.yml logs -f caddy
```

Common ACME failures:

- **DNS not resolving** to this box's IP — verify with `dig +short $DOMAIN`.
- **Cloud firewall blocking 80** — Let's Encrypt validates over plain HTTP first.
- **Cert rate-limited** — if you've retried more than 5×, wait an hour.

## Verifying

From your laptop:

```bash
curl https://$DOMAIN/health     # → {"status":"ok","hubId":"seed-1",...}
```

From a tribe install:

```bash
tribe seed set wss://$DOMAIN/gossip
tribe stop && tribe start
tribe peers                     # should show seed-1 as connected
```

## Operations

```bash
cd ~/tribe-seed/deploy/seed

# Logs
docker compose -f docker-compose.seed.yml logs -f hub
docker compose -f docker-compose.seed.yml logs -f caddy

# Restart (DOMAIN must be exported — Caddy needs it)
DOMAIN=seed.example.com docker compose -f docker-compose.seed.yml restart

# Stop
docker compose -f docker-compose.seed.yml down

# Update to latest TribeEco
cd ~/tribe-seed && git pull && git submodule update --init --recursive
cd deploy/seed && DOMAIN=seed.example.com docker compose -f docker-compose.seed.yml up -d --build
```

Cert renewal is automatic — Caddy handles it ~30 days before expiry without operator action.

## Files

- `Caddyfile` — single-block reverse proxy from `$DOMAIN` to `hub:4000`.
- `docker-compose.seed.yml` — three services: `hub-db`, `hub`, `caddy`. `hub` is internal-only (no published port).
- `setup-seed.sh` — bootstrap script for a fresh Ubuntu VPS.

## Adding more seeds

Multiple seeds give the mesh redundancy. To run a second one (say in the US):

1. Provision another VPS, point `seed-us.tribeapp.wtf` at it.
2. Run the same setup script with `DOMAIN=seed-us.tribeapp.wtf`.
3. (Optional) Update `DEFAULT_SEED_URL` in `bin/tribe` to a list and have the CLI try each in order — currently it's a single URL.

## Related Docs

- [TribeEco root README](../../Readme.md) — full architecture overview and distributed network setup
- [tribe-hub README](../../tribe-hub/README.md) — hub environment variables and gossip configuration
