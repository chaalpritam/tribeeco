# TribeEco

Decentralized social protocol on Solana. Mono-repo with submodules.

## Architecture

- **tribe-protocol/** — Solana programs (Anchor/Rust). 4 programs: tid-registry, app-key-registry, username-registry, social-graph.
- **tribe-sdk/** — TypeScript SDK. DirectSolana and EphemeralRollup providers.
- **tribe-hub/** — Decentralized hub. Tweet storage + Solana indexer + gossip peer sync. Fastify + PostgreSQL.
- **tribe-er-server/** — Ephemeral Rollup sequencer. Instant follows, batched L1 settlement every 10s. Fastify + PostgreSQL.
- **tribe-app/** — Next.js 16 demo frontend. Kept as a submodule for monorepo devs, but **not bundled with `brew install tribe`** — ships separately as `brew install tribe-app`.
- **homebrew-tap/** — Homebrew formulas for `brew install tribe` (hub + ER) and `brew install tribe-app` (demo UI).

## CLI (bin/tribe)

The main CLI script at `bin/tribe` manages the hub + ER stack (no frontend). Key commands:

- `tribe start` — Boots Docker services (hub-db, er-db, hub, er-server), waits for health, auto-connects to seed node.
- `tribe stop` — Stops Docker services.
- `tribe doctor` — Checks all prerequisites. Auto-generates wallet if missing.
- `tribe seed set <url>` — Sets seed node URL in `~/.tribe/seed`. Auto-connects on next start.
- `tribe peer add <url>` — POSTs to `http://localhost:4000/v1/peers` to connect hubs.
- `tribe peers` — Shows connected peers via `GET /v1/peers`.
- `tribe network` — Shows local, LAN, and seed node URLs.
- `tribe share` — Print copy-paste hub/ER URLs + reachability self-check for handing the stack to other devices on Wi-Fi.

The frontend used to boot as part of `tribe start` (port 3002). It now ships as a separate `tribe-app` formula — `tribe` no longer touches the frontend. To run the UI: `brew install tribe-app && tribe-app`.

## CLI (tribe-app)

The `tribe-app` formula installs a wrapper at `bin/tribe-app`:

- `tribe-app` — boots Next.js dev server on `$PORT` (default 3002). Sources `~/.tribe/tribe-app.env` if present so hub URL persists across runs.
- `tribe-app link <hub-url>` — writes `~/.tribe/tribe-app.env` with `NEXT_PUBLIC_HUB_URL` + `NEXT_PUBLIC_ER_SERVER_URL` derived from the hub URL. Used to point the demo UI at a hub on another LAN machine.

## Distributed Network

Nodes connect through a **seed node** — a hub running on a VPS with a public IP.

- Seed node config: `deploy/seed/docker-compose.seed.yml` (hub + hub-db only, HUB_ID: seed-1)
- Setup script: `deploy/seed/setup-seed.sh`
- Home nodes connect outbound to the seed via WebSocket gossip (`ws://<IP>:4000/gossip`)
- No inbound ports needed on home nodes — WebSocket is bidirectional
- Gossip is pull-based: hello → have → want → messages
- Hub peer manager handles reconnection with exponential backoff

## Homebrew Formulas

Two formulas, each mirrored in two locations:

**`tribe`** (hub + ER + protocol + SDK):
- `homebrew-tap/Formula/tribe.rb` — what brew actually uses (from the `homebrew-tribe` repo)
- `Formula/tribe.rb` — local copy for reference
- Source: `https://github.com/chaalpritam/TribeEco.git` (this repo)
- Deps: node, pnpm, docker, docker-compose, colima, solana. Tailscale optional.
- `install` clones every submodule **except `tribe-app`** (which has its own formula).
- `post_install` restores ER server wallet from `~/.tribe/server-wallet.json`.

**`tribe-app`** (Next.js demo UI):
- `homebrew-tap/Formula/tribe-app.rb` — what brew uses
- `Formula/tribe-app.rb` — local copy for reference
- Source: `https://github.com/chaalpritam/tribe-demo-app.git` (the standalone repo, not via the TribeEco monorepo)
- Deps: node, pnpm.
- `install` writes `bin/tribe-app` wrapper that supports `run` (default) and `link <hub-url>` subcommands.
- `post_install` runs `pnpm install` in `libexec`.

Formula changes must be pushed to BOTH the `homebrew-tap` submodule AND the main repo (the local copies are reference-only — `homebrew-tap/Formula/*.rb` is the live one).

## Persistent State (~/.tribe/)

- `~/.tribe/server-wallet.json` — ER server Solana keypair. Survives reinstalls.
- `~/.tribe/seed` — Seed node WebSocket URL. One line, e.g. `ws://1.2.3.4:4000/gossip`.
- `~/.tribe/tribe-app.env` — `NEXT_PUBLIC_HUB_URL` + `NEXT_PUBLIC_ER_SERVER_URL` for the `tribe-app` demo UI. Written by `tribe-app link <hub-url>`, sourced on every `tribe-app` run.

## Key Ports

| Service | Port | Owned by |
|---|---|---|
| Demo frontend (Next.js) | 3002 | `tribe-app` formula (separate install) |
| ER Server | 3003 | `tribe` |
| Hub API | 4000 | `tribe` |
| ER Database (Postgres) | 5435 | `tribe` |
| Hub Database (Postgres) | 5436 | `tribe` |

## Submodule Remotes

Submodules use HTTPS URLs in `.gitmodules` (for unauthenticated cloning). For pushing, use the `chaalpritam` SSH remote (e.g. `git push chaalpritam master`). The `origin` remote is HTTPS and can't push without credentials.

## Docker

- Root `docker-compose.yml` runs the full stack: er-db, hub-db, er-server, hub.
- The demo frontend (`tribe-app`) runs outside Docker via `pnpm dev` and is now a separate brew formula — not part of `tribe start`.
- `deploy/seed/docker-compose.seed.yml` runs only hub + hub-db for seed nodes.

## Hub Gossip Protocol

- Peers configured via `PEERS` env var (comma-separated WebSocket URLs) or `POST /v1/peers` API.
- WebSocket endpoint: `GET /gossip`
- Client WebSocket: `GET /v1/ws`
- Sync state tracked per peer in `sync_state` table.
- Config: GOSSIP_INTERVAL_MS (5s), RECONNECT_DELAY_MS (10s), PING_INTERVAL_MS (30s).
