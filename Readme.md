# TribeEco

**A fully-owned, open social protocol on Solana.**

## Overview

TribeEco is a decentralized social protocol built on Solana. It provides on-chain identity (TID), delegated app keys, human-readable usernames (.tribe), a social graph with an Ephemeral Rollup sequencer, and off-chain tweet storage with peer-to-peer gossip sync. The protocol is designed so that users fully own their identity and social data -- no platform can revoke access or censor content at the infrastructure layer.

## Architecture

```
                        Users / Apps
                             |
                       tribe-sdk (TypeScript)
                       /         |          \
           tribe-app        tribe-er-server   tribe-hub
           (frontend)       (ER sequencer)    (tweets + indexing + gossip)
                \              |                /
  ┌──────────────┴─────────────┴───────────────┴────┐
  |                Solana Programs                   |
  |  tid-registry . app-key-registry                 |
  |  username-registry . social-graph                |
  └──────────────────────────────────────────────────┘
```

See [HOW-IT-WORKS.md](./HOW-IT-WORKS.md) for a detailed walkthrough of every layer and how they connect.

## Repos

| Directory | Description |
|-----------|-------------|
| [tribe-protocol](./tribe-protocol) | Solana programs (Anchor) -- 5 programs, 23 instructions (identity, keys, usernames, social graph, hub registry) |
| [tribe-sdk](./tribe-sdk) | TypeScript SDK -- DirectSolana and EphemeralRollup providers, identity clients, tweet client |
| [tribe-hub](./tribe-hub) | Decentralized hub -- combined tweet storage + indexer + gossip peer sync |
| [tribe-er-server](./tribe-er-server) | Ephemeral Rollup sequencer -- instant follows, batched L1 settlement every 10s |
| [tribe-app](./tribe-app) | Next.js frontend -- 10 pages: feed, explore, channels, profile, threads, search, DMs, notifications, bookmarks, settings |

## Run a Tribe Node

### macOS (Homebrew)

Works on MacBook, Mac Mini, Mac Pro (Intel or Apple Silicon).

```bash
brew tap chaalpritam/tribe
brew install tribe
tribe start
```

Auto-installs all dependencies (Docker, Colima, Node.js, pnpm, Solana CLI), generates a server wallet, and boots all services.

```bash
tribe seed set ws://<SEED_IP>:4000/gossip   # connect to the network
tribe peers                                  # verify connection
tribe network                                # show all URLs
```

### Raspberry Pi

Works on Raspberry Pi 4 (4GB+) and Raspberry Pi 5 with Raspberry Pi OS 64-bit.

**One-line install:**

```bash
curl -fsSL https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/raspberry-pi/setup.sh | bash
```

**Or step by step:**

```bash
git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git ~/tribe
cd ~/tribe/deploy/raspberry-pi
./setup.sh
```

After setup, connect to the network:

```bash
curl -X POST http://localhost:4000/v1/peers \
  -H "Content-Type: application/json" \
  -d '{"url": "ws://<SEED_IP>:4000/gossip"}'
```

Auto-start on boot:

```bash
sudo systemctl enable docker
crontab -e   # add: @reboot cd ~/tribe && docker compose up -d
```

### Seed Node (VPS)

The seed node is the public entry point for the network. Deploy on any VPS with a public IP (Oracle Cloud free tier, DigitalOcean, Hetzner).

```bash
ssh ubuntu@<VPS_IP>
git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git ~/tribe-seed
cd ~/tribe-seed/deploy/seed
./setup-seed.sh
```

The seed prints its gossip URL. Share it with all node operators:

```
ws://<PUBLIC_IP>:4000/gossip
```

### Docker (any platform)

```bash
git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git
cd TribeEco
docker-compose up -d        # Start hub, ER server, and databases
cd tribe-app && pnpm install && pnpm dev -p 3002   # Start frontend (optional)
```

## Build from Source

### On-chain programs

```bash
cd tribe-protocol
pnpm install
anchor build
anchor test          # 23 integration tests against local validator
```

### SDK

```bash
cd tribe-sdk
pnpm install
pnpm run build
```

## Devnet Deployment

All 4 programs are deployed to Solana devnet:

| Program | Program ID | Instructions |
|---------|------------|-------------|
| tid-registry | `4BSmJmRGQWKgioP9DG2bUuRS9U3V6soRauU7Nv6yGvHD` | 5 |
| app-key-registry | `5LtbFUeAoXWRovGpyWnRJhiCS62XsTYKVErT9kPpv4hN` | 3 |
| username-registry | `65oKjSjcGYR61ASzDYczbodz6H8TARtJyQGvb5V9y9W1` | 4 |
| social-graph | `8kKnWvbmTjWq5uPePk79RRbQMAXCszNFzHdRwUS4N74w` | 7 |

The ER sequencer authority is registered on devnet with a funded server wallet.

## Key Concepts

### TID (Tribe ID)

Every user receives a unique auto-incrementing 64-bit numeric identity. Each TID has a custody address (primary wallet) and a recovery address (can reclaim the TID if the custody key is lost). TIDs are the universal identifier across the entire protocol.

### Tweets

Messages are signed with ed25519 app keys and hashed with BLAKE3. Tweets are stored off-chain in the hub for throughput and cost efficiency, while the on-chain identity layer guarantees authorship and integrity. The hub validates every signature against on-chain app key records.

### Social Graph

Uses a PDA-per-relationship design. Each follow is a tiny on-chain account (Link, 33 bytes) seeded by `["link", follower_tid, following_tid]`. This gives O(1) follow, O(1) unfollow, O(1) existence checks, unlimited follows per user, and rent reclamation on unfollow.

### Ephemeral Rollup (ER)

The ER server is a sequencer that accepts follow/unfollow requests signed by custody wallets, confirms them instantly (optimistic), then batches them into Solana L1 transactions every 10 seconds. Users get sub-50ms follow confirmations while the on-chain state eventually settles. The ER server uses `follow_delegated` and `unfollow_delegated` instructions that accept a registered sequencer authority.

### App Keys

Scoped delegation keys that let applications sign messages on behalf of a user. Each key has a permission scope (Full, TweetsOnly, SocialOnly, ReadOnly) and an optional expiry. Users can revoke or rotate keys at any time.

### Usernames (.tribe)

Human-readable names bound to TIDs. Usernames are up to 20 characters, require annual renewal, and can be transferred or released. A reverse lookup maps each TID to its current username.

## Services

| Service | Port | Description |
|---------|------|-------------|
| tribe-hub | 4000 | Tweet storage + indexing + gossip sync |
| tribe-app | 3002 | Next.js frontend |
| tribe-er-server | 3003 | ER sequencer + settlement |

## Tech Stack

- **Rust / Anchor 0.31.1** -- on-chain Solana programs (5 programs, 23 instructions)
- **TypeScript** -- SDK, tests, server applications, frontend
- **Fastify** -- HTTP server framework (hub, ER server)
- **PostgreSQL 16** -- off-chain storage (2 databases: hub state, ER pending ops)
- **Next.js 16 / React 19** -- frontend with Tailwind CSS 4
- **Solana wallet adapter** -- Phantom, Solflare wallet connection
- **tweetnacl** -- ed25519 signature signing and verification
- **BLAKE3** -- content-addressable hashing for tweets
- **Protocol Buffers** -- message encoding in the SDK

## CLI Commands

```bash
tribe start          # boot all services
tribe stop           # shut everything down
tribe status         # check what's running
tribe doctor         # verify prerequisites
tribe logs [svc]     # tail logs (hub, er-server, app, all)
tribe seed set <url> # set seed node for network auto-connect
tribe peers          # show connected hub peers
tribe peer add <url> # connect to another hub
tribe network        # show all access URLs (local, LAN, seed)
tribe reset          # wipe data and start fresh
```

## Distributed Network

TribeEco nodes discover each other through a **seed node** — a lightweight hub running on a VPS with a public IP. Home nodes auto-connect to the seed on startup, and the gossip protocol handles peer discovery and message sync.

### Deploy a seed node (free Oracle Cloud VPS)

```bash
ssh ubuntu@<VPS_IP>
git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git
cd TribeEco/deploy/seed
./setup-seed.sh
```

### Connect nodes to the seed

```bash
tribe seed set ws://<SEED_IP>:4000/gossip
tribe start
```

All nodes connected to the seed automatically sync via the gossip protocol.

### Direct peer connections (same network)

```bash
tribe peer add ws://192.168.1.10:4000/gossip
```

### Connect your web app

Point your app to the seed node's public API:

```
Hub API:    http://<SEED_IP>:4000
ER Server:  http://<SEED_IP>:3003
```

## Documentation

- [DEVELOPER-GUIDE.md](./DEVELOPER-GUIDE.md) -- build apps on Tribe: SDK reference, API docs, hub setup, examples
- [HOW-IT-WORKS.md](./HOW-IT-WORKS.md) -- detailed architecture walkthrough with data flow diagrams
- [HOW-TO-RUN.md](./HOW-TO-RUN.md) -- local and multi-node deployment guide
- [TODO.md](./TODO.md) -- project status and remaining work

## License

MIT
