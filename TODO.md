# TribeEco — Project Status & Plan

## Current State

### tribe-protocol (Anchor/Rust) — Done
All 4 on-chain programs fully implemented and deployed to devnet:
- `tid-registry` (5 instructions), `app-key-registry` (3), `username-registry` (4), `social-graph` (7)
- Social graph now includes delegated instructions for ER: `init_sequencer`, `init_profile_delegated`, `follow_delegated`, `unfollow_delegated`
- 23 integration tests passing (all programs)
- Cross-program TID reads use manual deserialization with owner verification
- Anchor 0.31.1, Rust nightly

### tribe-sdk (TypeScript) — Done
- All identity clients implemented (TID, AppKey, Username) using Anchor IDL
- Social graph client with two providers: `DirectSolanaProvider` (L1) and `EphemeralRollupProvider` (ER)
- Tweet client implemented (publish, query, search)
- Protobuf compiled from `proto/message.proto` → TypeScript bindings
- Blake3 hashing, ed25519 message signing and verification

### tribe-er-server (Fastify/Node.js) — Done
- Ephemeral Rollup sequencer for social graph operations
- Accepts follow/unfollow requests signed by custody wallets (ed25519 verification)
- Optimistic local state (instant reads for pending operations)
- Batched settlement to Solana L1 every 10s via `follow_delegated`/`unfollow_delegated`
- Auto-initializes missing social profiles during settlement
- On-chain fallback for reads, crash recovery via Postgres
- Registered sequencer authority on devnet

### tribe-twitter-app (Next.js) — Done
- 6 pages: Home (feed + composer), Explore (user list), Channels, Profile, Tweet thread, Search
- Wallet connection via Solana wallet adapter (Phantom, Solflare)
- 3-step registration: TID → username (.tribe) → signing key
- Tweet posting with blake3 hashing + ed25519 signing
- Follow/unfollow via ER server (instant optimistic updates)
- Like reactions, reply support, channel posting
- Clickable usernames → profile pages, followers/following tabs
- Auto-refresh feed every 15s, dark theme, responsive layout

## Completed Tasks

- [x] 1. Install dependencies — `pnpm install` in each Node project
- [x] 2. `anchor build` — Generate IDL types (upgraded to Anchor 0.31.1)
- [x] 3. Create DB migration files — Added migration runner to all servers
- [x] 4. Implement indexer event processors — Discriminator matching + deserialization
- [x] 5. Implement SDK client methods — TID, AppKey, Username, SocialGraph using IDL
- [x] 6. Compile protobuf — Generated TS types + replaced JSON/SHA-512 placeholders
- [x] 7. Write integration tests — All 4 Anchor programs (23 tests passing)
- [x] 8. Fill in tweet-server TODOs — Dedup, storage limits, reactions, app key deserialization
- [x] 9. Rename FID→TID, Cast→Tweet across entire codebase
- [x] 10. Deploy all 4 programs to Solana devnet
- [x] 11. End-to-end smoke test on devnet
- [x] 12. Build demo frontend (tribe-twitter-app)
- [x] 13. Add social features — follow/unfollow, likes, replies, channels, search
- [x] 14. Add ER server — delegated instructions, sequencer, batched settlement
- [x] 15. Wire ER into frontend — instant optimistic follows
- [x] 16. Production prep — Docker, env vars, CORS, rate limiting

## Remaining Work

- [ ] Security audit of on-chain programs before mainnet
- [ ] Integration tests for SDK, hub, ER server
- [ ] Mainnet deployment with multisig upgrade authority
- [ ] Media uploads (IPFS/Arweave for images)
- [ ] Real-time updates (WebSocket/SSE replacing polling)
- [ ] Mobile app (React Native using the SDK)
