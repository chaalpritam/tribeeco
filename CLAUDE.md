# TribeEco

Decentralized social protocol on Solana. Mono-repo with submodules.

## Architecture

- **tribe-protocol/** — Solana programs (Anchor/Rust). 4 programs: tid-registry, app-key-registry, username-registry, social-graph.
- **tribe-sdk/** — TypeScript SDK. DirectSolana and EphemeralRollup providers.
- **tribe-hub/** — Decentralized hub. Tweet storage + Solana indexer + gossip peer sync. Fastify + PostgreSQL.
- **tribe-er-server/** — Ephemeral Rollup sequencer. Instant follows, batched L1 settlement every 10s. Fastify + PostgreSQL.
- **tribe-app/** — Next.js 16 frontend. React 19, Tailwind CSS 4, Solana wallet adapter.
- **homebrew-tap/** — Homebrew formula for `brew install tribe`.

## CLI (bin/tribe)

The main CLI script at `bin/tribe` manages the full stack. Key commands:

- `tribe start` — Boots Docker services, waits for health, auto-connects to seed node, starts frontend.
- `tribe stop` — Stops frontend, Docker services.
- `tribe doctor` — Checks all prerequisites. Auto-generates wallet if missing.
- `tribe seed set <url>` — Sets seed node URL in `~/.tribe/seed`. Auto-connects on next start.
- `tribe peer add <url>` — POSTs to `http://localhost:4000/v1/peers` to connect hubs.
- `tribe peers` — Shows connected peers via `GET /v1/peers`.
- `tribe network` — Shows local, LAN, and seed node URLs.

## Distributed Network

Nodes connect through a **seed node** — a hub running on a VPS with a public IP.

- Seed node config: `deploy/seed/docker-compose.seed.yml` (hub + hub-db only, HUB_ID: seed-1)
- Setup script: `deploy/seed/setup-seed.sh`
- Home nodes connect outbound to the seed via WebSocket gossip (`ws://<IP>:4000/gossip`)
- No inbound ports needed on home nodes — WebSocket is bidirectional
- Gossip is pull-based: hello → have → want → messages
- Hub peer manager handles reconnection with exponential backoff

## Homebrew Formula

Two copies of the formula:
- `homebrew-tap/Formula/tribe.rb` — The one brew actually uses (from the `homebrew-tribe` repo)
- `Formula/tribe.rb` — Local copy for reference

Dependencies: node, pnpm, docker, docker-compose, colima, solana. Tailscale is optional.

`post_install` clones submodules and restores wallet from `~/.tribe/server-wallet.json`.

Brew formula changes must be pushed to BOTH the homebrew-tap submodule AND the main repo.

## Persistent State (~/.tribe/)

- `~/.tribe/server-wallet.json` — ER server Solana keypair. Survives reinstalls.
- `~/.tribe/seed` — Seed node WebSocket URL. One line, e.g. `ws://1.2.3.4:4000/gossip`.

## Key Ports

| Service | Port |
|---|---|
| Frontend (Next.js) | 3002 |
| ER Server | 3003 |
| Hub API | 4000 |
| ER Database (Postgres) | 5435 |
| Hub Database (Postgres) | 5436 |

## Submodule Remotes

Submodules use HTTPS URLs in `.gitmodules` (for unauthenticated cloning). For pushing, use the `chaalpritam` SSH remote (e.g. `git push chaalpritam master`). The `origin` remote is HTTPS and can't push without credentials.

## Docker

- Root `docker-compose.yml` runs the full stack: er-db, hub-db, er-server, hub.
- Frontend runs outside Docker via `pnpm dev`.
- `deploy/seed/docker-compose.seed.yml` runs only hub + hub-db for seed nodes.

## Hub Gossip Protocol

- Peers configured via `PEERS` env var (comma-separated WebSocket URLs) or `POST /v1/peers` API.
- WebSocket endpoint: `GET /gossip`
- Client WebSocket: `GET /v1/ws`
- Sync state tracked per peer in `sync_state` table.
- Config: GOSSIP_INTERVAL_MS (5s), RECONNECT_DELAY_MS (10s), PING_INTERVAL_MS (30s).
