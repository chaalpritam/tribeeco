# TribeEco production node on AWS (EC2 + Docker Compose)

A public, always-on TribeEco node — **hub + ER server** — fronted by
Caddy for automatic TLS. This is the node "anyone from anywhere" uses:

- **Access an existing hub** → clients point at `wss://$DOMAIN/gossip`
  (gossip) and `https://$DOMAIN:3003` (ER server). Home Macs running
  `tribe start` connect *outbound*, so they need no inbound ports.
- **Set up their own hub** → `brew install tribe && tribe start`, then
  `tribe seed set wss://$DOMAIN/gossip` to bootstrap into this mesh.

Unlike `deploy/seed/` (hub-only), this runs the **ER server** too, so
follows/unfollows settle to Solana L1 from the public node.

## Topology

```
              Internet
                 │  443 (https + wss)   3003 (https)
                 ▼
          ┌──────────────┐
          │    Caddy     │  Let's Encrypt TLS for $DOMAIN
          └──────┬───────┘
        hub:4000 │ er-server:3003   (internal docker network)
        ┌────────┴─────────┐
        ▼                  ▼
   ┌─────────┐        ┌──────────┐
   │   hub   │◄──────►│ er-server│  → Solana devnet (settlement)
   └────┬────┘        └────┬─────┘
        ▼                  ▼
    hub-db (pg)         er-db (pg)     EBS-backed docker volumes
```

## Provisioning: Terraform (recommended) or manual

The fastest path is the Terraform in `terraform/` — it creates the EC2
instance, Elastic IP, security group (**including port 3003**), and
optionally the Route 53 A record, then runs `setup-aws.sh` on first boot
via cloud-init. The box comes up fully configured.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit domain, key_name, ssh IP, password
terraform init
terraform apply
```

`terraform output next_steps` prints exactly what to do after. If you set
`route53_zone_id`, DNS is handled too; otherwise point your A record at
`terraform output elastic_ip`.

Prefer clicking through the console? The manual steps below produce the
same result.

## 1. Provision the EC2 instance

| Setting | Recommendation |
|---|---|
| AMI | Ubuntu Server 22.04 LTS (x86_64) |
| Instance type | `t3.medium` (4 GB) — `t3.small` works but is tight with 2× Postgres + 2 Node services |
| Storage | 30 GB gp3 root volume |
| Elastic IP | Allocate one and associate it (so the IP survives stop/start) |
| Key pair | Your SSH key |

**Security group inbound rules:**

| Port | Source | Why |
|---|---|---|
| 22 | your IP only | SSH |
| 80 | 0.0.0.0/0 | Let's Encrypt ACME HTTP-01 challenge |
| 443 | 0.0.0.0/0 | hub API + `wss` gossip |
| **3003** | 0.0.0.0/0 | **ER server (don't forget this one)** |

Outbound: allow all (needs to reach Solana RPC + Let's Encrypt).

## 2. DNS

Point an **A record** for `$DOMAIN` at the Elastic IP.

- **Route 53:** create/confirm a hosted zone for your domain, add an
  `A` record `seed.tribeprotocol.xyz → <Elastic IP>`. If your registrar
  is elsewhere, either delegate NS to Route 53 or just add the A record
  at your current DNS provider.
- Wait until `dig +short seed.tribeprotocol.xyz` returns the Elastic IP
  **before** running setup — Caddy's cert issuance needs DNS to resolve.

## 3. Install

SSH in and run:

```bash
DOMAIN=seed.tribeprotocol.xyz bash <(curl -fsSL \
  https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/prod/setup-aws.sh)
```

The script: installs Docker + Solana CLI → clones the repo to
`~/tribe-prod` → generates and **airdrops a devnet wallet** for the ER
server → builds and starts `hub-db`, `er-db`, `er-server`, `hub`,
`caddy` → opens host firewall 80/443/3003 → verifies both public
endpoints.

First boot takes ~60s while Caddy negotiates two certs.

## 4. Verify

```bash
curl https://seed.tribeprotocol.xyz/health        # {"status":"ok","hubId":"seed-aws-1",...}
curl https://seed.tribeprotocol.xyz:3003/health   # ER server ok
```

From any laptop with `brew install tribe`:

```bash
tribe seed set wss://seed.tribeprotocol.xyz/gossip
tribe stop && tribe start
tribe peers          # should list seed-aws-1
```

Demo web app:

```bash
brew install tribe-twitter-app
tribe-twitter-app link https://seed.tribeprotocol.xyz   # ER auto-derived as :3003
tribe-twitter-app
```

## 5. Make this the default seed (optional)

So fresh `brew install tribe` users join *your* mesh automatically,
update `bin/tribe`:

```bash
DEFAULT_SEED_URL="wss://seed.tribeprotocol.xyz/gossip"
```

(line ~32). Commit + push so the formula picks it up.

## ER server wallet & funding

The ER server signs L1 settlement transactions, so its wallet must hold
SOL. On devnet that's free but rate-limited:

```bash
# wallet pubkey
solana-keygen pubkey ~/tribe-prod/deploy/prod/server-wallet.json

# top up (repeat if airdrop is throttled, or use faucet.solana.com)
solana airdrop 2 <PUBKEY> --url https://api.devnet.solana.com
```

Watch the balance — if it hits 0, follows stop settling. A simple cron
that airdrops when low is enough for a devnet demo. **`server-wallet.json`
is a private key: it's gitignored, never commit it, and back it up.**

## Operations

```bash
cd ~/tribe-prod/deploy/prod

# logs
docker compose -f docker-compose.prod.yml logs -f hub er-server
docker compose -f docker-compose.prod.yml logs -f caddy

# restart (DOMAIN must be set — Caddy needs it)
DOMAIN=seed.tribeprotocol.xyz docker compose -f docker-compose.prod.yml restart

# update to latest
cd ~/tribe-prod && git pull && git submodule update --init --recursive
cd deploy/prod && DOMAIN=seed.tribeprotocol.xyz \
  docker compose -f docker-compose.prod.yml up -d --build
```

Cert renewal is automatic (Caddy, ~30 days before expiry).

## Backups

State lives in two docker volumes (`hub-pgdata`, `er-pgdata`) and
`hub-media` on the EBS root volume.

- **Quick:** nightly cron `pg_dump` to S3:
  ```bash
  docker compose -f docker-compose.prod.yml exec -T hub-db \
    pg_dump -U tribe tribe_hub | gzip | aws s3 cp - s3://YOUR_BUCKET/hub-$(date +%F).sql.gz
  ```
- **Disk-level:** schedule EBS snapshots via AWS Backup / DLM.
- The ER DB is largely re-derivable from L1, but back it up too to avoid
  re-settling in-flight follows.

## Production hardening (next steps, in priority order)

1. **Dedicated Solana RPC.** Public devnet throttles hard. A Helius /
   Triton / QuickNode devnet endpoint in `SOLANA_RPC_URL` /
   `SOLANA_WS_URL` removes the main reliability risk.
2. **Media → S3.** `MEDIA_DIR` is a local volume today; for durable,
   scalable uploads move the hub's upload pipeline (`tribe-hub/src/api/
   routes/upload.ts`) to S3. Until then, EBS snapshots cover it.
3. **Postgres → RDS.** Swap the in-container Postgres for RDS (point
   `DATABASE_URL` at it) for managed backups, failover, and PITR.
4. **Monitoring.** Ship container logs to CloudWatch; alert on the
   `/health` endpoints and on the ER wallet balance.
5. **Multi-region redundancy.** Run a second node (different `HUB_ID`,
   different `$DOMAIN`) and set `PEERS` on each to the other — the
   gossip mesh keeps them in sync. See `../seed/README.md` § "Adding
   more seeds".

## Files

- `docker-compose.prod.yml` — hub-db, er-db, er-server, hub, caddy.
- `Caddyfile` — TLS for `$DOMAIN` (hub on 443) and `$DOMAIN:3003` (ER).
- `setup-aws.sh` — one-shot bootstrap for a fresh Ubuntu EC2 box.
- `.env.prod.example` — copy to `.env` and edit.

## Related

- `../seed/README.md` — the lighter hub-only seed (no ER server).
- `../../Readme.md` — full architecture overview.
- `../../tribe/README.md` — hyperlocal iOS client (`app.tribe.app`).
- `../../tribe-twitter/README.md` — Twitter-shaped iOS client (`app.tribe.twitter`).
