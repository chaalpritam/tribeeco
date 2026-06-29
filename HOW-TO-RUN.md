# How to Run TribeEco

## Prerequisites

- Node.js 18+
- pnpm
- Docker & Docker Compose
- Rust + Anchor CLI (for Solana programs only)

---

## Quick Start

```bash
./start.sh    # starts everything — open http://localhost:3002
./stop.sh     # stops everything
```

---

## Option 1: Docker (Full Stack)

Spins up the hub, ER server, and all Postgres databases in one command.

```bash
docker-compose up -d
```

| Service      | Port  |
|--------------|-------|
| Hub          | 4000  |
| ER server    | 3003  |
| Hub DB       | 5436  |
| ER DB        | 5435  |

### Verify

```bash
curl http://localhost:4000/health
curl http://localhost:3003/health
```

---

## Option 2: Run Services Individually

### 1. Solana Programs

```bash
cd tribe-protocol
anchor build
anchor test
```

### 2. SDK

```bash
cd tribe-sdk
pnpm install
pnpm build
pnpm test
```

### 3. Hub

The hub handles tweet storage, indexing, and peer-to-peer gossip sync.

```bash
cd tribe-hub
cp .env.example .env    # edit with your DB/RPC config
docker-compose up -d    # start Postgres
pnpm install
pnpm dev                # starts on port 4000
```

### 4. ER Server

```bash
cd tribe-er-server
cp .env.example .env
docker-compose up -d    # start Postgres
pnpm install
pnpm dev                # starts on port 3003
```

### 5. Frontend App

```bash
cd tribe-twitter-app
pnpm install
pnpm dev                # Next.js on port 3002
```

Open http://localhost:3002 in your browser.

---

## Startup Order

If running everything locally without Docker, start in this order:

1. Postgres databases
2. Hub
3. ER server
4. Frontend app

---

## Running Tests

```bash
# SDK
cd tribe-sdk && pnpm test

# Hub
cd tribe-hub && pnpm test

# ER server
cd tribe-er-server && pnpm test

# Solana programs
cd tribe-protocol && anchor test
```

---

## Port Summary

| Service         | Port |
|-----------------|------|
| Frontend app    | 3002 |
| ER server       | 3003 |
| Hub             | 4000 |
| ER DB           | 5435 |
| Hub DB          | 5436 |

---

## Environment Variables

Each service has a `.env.example` file. Copy and edit before running:

```bash
cp .env.example .env
```

Key variables shared across services:

| Variable                       | Description                        |
|--------------------------------|------------------------------------|
| `SOLANA_RPC_URL`               | Solana RPC endpoint                |
| `SOLANA_CLUSTER`               | `devnet` or `mainnet`              |
| `DATABASE_URL`                 | PostgreSQL connection string       |
| `TID_REGISTRY_PROGRAM_ID`      | TID registry program address       |
| `APP_KEY_REGISTRY_PROGRAM_ID`  | App key registry program address   |
| `SOCIAL_GRAPH_PROGRAM_ID`      | Social graph program address       |
| `USERNAME_REGISTRY_PROGRAM_ID` | Username registry program address  |

---

## Cross-device dev (same Wi-Fi)

For the common solo-dev setup — protocol on a Mac mini, frontend dev on a MacBook Air, native iOS testing on iPhone, all on the same Wi-Fi — only the machine running the stack needs `tribe` installed. The dev laptop just needs its `tribe-twitter-app` checkout and two env vars.

**Use the LAN IP, not `*.local`, for the dev frontend's env vars.** Chrome's `fetch()` trips on macOS' IPv6 link-local record for `.local` names and surfaces `ERR_ADDRESS_UNREACHABLE`; the IPv4 has no such hazard. The hostname is still fine for `ping` / `curl` / iPhone Safari.

```bash
# On the machine running the stack (e.g. Mac mini):
tribe start
tribe share          # prints copy-paste URLs (uses IPv4 for the .env.local block)
tribe share --qr     # also renders a QR for the frontend (brew install qrencode)

# On the dev laptop — paste from `tribe share` output (substitute the actual IP):
cat > .env.local <<EOF
NEXT_PUBLIC_HUB_URL=http://192.168.1.6:4000
NEXT_PUBLIC_ER_SERVER_URL=http://192.168.1.6:3003
EOF
cd tribe-twitter-app && pnpm dev               # http://localhost:3002 talks to the remote hub

# On iPhone (same Wi-Fi):
#   Web app: open http://yourmac.local:3002 in Safari (Safari handles the IPv6 fallback)
#   Native:  put http://192.168.1.6:4000 in the app's Hub URL field
```

If you do also have `tribe` installed on the dev laptop, `tribe link http://192.168.1.6:4000` writes that `.env.local` in one command, and `tribe link --check <url>` probes the remote stack without writing anything.

`tribe share` prefers the Bonjour `*.local` hostname over the LAN IP because it survives DHCP lease changes and resolves natively on macOS + iOS. The IP is shown as a fallback for clients that don't speak `.local`. The hub's CORS is wide-open in dev (`NODE_ENV != production`), so cross-origin from another device's frontend works without configuration.

For "anywhere" access (e.g. iPhone over cellular), use a tunnel — that's the `## Multi-Node Deployment` flow below, which uses Cloudflare Tunnel.

---

## Multi-Node Deployment (2 Macs)

Run TribeEco on 2 Mac machines for high availability. If one goes down, the other keeps serving.

### Architecture

```
    Vercel (frontend)
     |            |
hub-a.domain  hub-b.domain     ← Cloudflare Tunnels
     |            |
  Mac Air      Mac Mini
  Hub+ER+PG    Hub+ER+PG       ← Each runs all services
     |            |
     └── gossip ──┘             ← Hubs sync via gossip protocol
```

### Prerequisites

- 2 Macs on any network (no port forwarding needed)
- A domain on Cloudflare (free plan works)
- The same `server-wallet.json` on both machines

### Setup Steps

**1. Clone the repo on both Macs:**

```bash
git clone <repo-url> TribeEco
cd TribeEco
```

**2. Configure this node:**

```bash
cp deploy/.env.node.example deploy/.env.node
# Edit deploy/.env.node:
#   HUB_ID=hub-air          (or hub-mini for the other machine)
#   NODE_PREFIX=hub-a        (or hub-b)
#   PEER_HUB_URL=wss://hub-b.yourdomain.com/gossip
#   DOMAIN=yourdomain.com
```

**3. Set up Cloudflare Tunnel (one-time per machine):**

```bash
# Authenticate
cloudflared tunnel login

# Create tunnel (e.g., tribe-hub-a)
cloudflared tunnel create tribe-hub-a

# Add DNS routes
cloudflared tunnel route dns tribe-hub-a hub-a.yourdomain.com
cloudflared tunnel route dns tribe-hub-a er-a.yourdomain.com
```

**4. Run the setup script:**

```bash
./deploy/setup-node.sh
```

This will:
- Start PostgreSQL containers
- Install dependencies
- Generate .env files for hub and er-server
- Create launchd plists for auto-start on boot

**5. Start services:**

```bash
launchctl load ~/Library/LaunchAgents/com.tribe.hub.plist
launchctl load ~/Library/LaunchAgents/com.tribe.er-server.plist
launchctl load ~/Library/LaunchAgents/com.tribe.cloudflared.plist
```

**6. Repeat steps 2-5 on the second Mac** (with `hub-b` / `hub-mini` values).

**7. Deploy frontend to Vercel:**

Set these environment variables in your Vercel project:

```
NEXT_PUBLIC_HUB_URLS=https://hub-a.yourdomain.com,https://hub-b.yourdomain.com
NEXT_PUBLIC_ER_SERVER_URLS=https://er-a.yourdomain.com,https://er-b.yourdomain.com
NEXT_PUBLIC_SOLANA_RPC_URL=https://api.devnet.solana.com
```

### How Failover Works

- **Frontend**: Tries Hub A first. If it fails (network error / timeout), automatically retries on Hub B. Dead nodes are rechecked every 30 seconds.
- **Hubs**: Gossip protocol syncs all tweets between nodes. Both hubs always have all data.
- **ER Servers**: Both accept follow/unfollow requests independently. Same server wallet means both can settle to Solana. PDA uniqueness prevents duplicates.

### Verify

```bash
# Check both hubs
curl https://hub-a.yourdomain.com/health
curl https://hub-b.yourdomain.com/health

# Check gossip
curl https://hub-a.yourdomain.com/v1/peers

# Check ER servers
curl https://er-a.yourdomain.com/health
curl https://er-b.yourdomain.com/health
```

### Logs

```bash
tail -f .logs/hub.log
tail -f .logs/er-server.log
tail -f .logs/cloudflared.log
```

### Stop Services

```bash
launchctl unload ~/Library/LaunchAgents/com.tribe.hub.plist
launchctl unload ~/Library/LaunchAgents/com.tribe.er-server.plist
launchctl unload ~/Library/LaunchAgents/com.tribe.cloudflared.plist
docker compose -f deploy/docker-compose.node.yml down
```
