# How TribeEco Works

## The Big Picture

```
┌────────────────────────────���────────────────────────────────────┐
│                        User's Browser                           │
│                        (tribe-app)                              │
│                                                                 │
│  Phantom Wallet <-> Next.js Frontend                            │
│       |                |           |            |               │
│       |          Tweet Post    Follow/Unfollow   Read Feed      │
│       |            (sign)      (sign message)    (fetch)        │
└───────┼────────────────┼───────────┼────────────┼───────────────┘
        |                |           |            |
        |                v           v            v
        |         ┌──────────┐ ┌──���───────┐ ┌──────────┐
        |         │   Hub    │ │    ER    │ │   Hub    │
        |         │  :4000   │ │  Server  │ │  :4000   │
        |         │ (submit) │ │  :3003   │ │  (read)  │
        |         └────┬─────┘ └────┬─────┘ └──────────┘
        |              |            |
        |              v            v
        |         PostgreSQL   PostgreSQL
        |         (hub state)  (pending
        |                       ops)
        |                       |
        |                       | every 10s
        |                       v
        |              ┌────────────────────────────┐
        └──────────────>      Solana Devnet          │
           on-chain    │                             │
           txns        │  tid-registry               │
           (register,  │  app-key-registry           │
            add key,   │  username-registry          │
            username)  │  social-graph               │
                       └────��────────────────────────┘
```

## Layer by Layer

---

## Layer 1: Solana Programs (On-Chain -- Permanent State)

Four programs store the ownership data that can never be taken away.

### tid-registry -- Your identity

```
User wallet -> register() -> TidRecord PDA
                              |-- tid: 9 (unique number)
                              |-- custody_address: your wallet
                              |-- recovery_address: backup wallet
```

This is like your passport number. The custody wallet controls it. If you lose your keys, the recovery address can reclaim it.

**Instructions:** initialize, register, transfer, recover, change_recovery

### app-key-registry -- Delegated signing

```
User wallet -> addAppKey() -> AppKeyRecord PDA
                                |-- tid: 9
                                |-- app_pubkey: ed25519 key
                                |-- scope: Full/TweetsOnly/SocialOnly
                                |-- expires_at: optional expiry
```

Instead of signing every tweet with your main wallet, you generate a lightweight ed25519 keypair and register it on-chain. Apps use this key to sign messages on your behalf. You can revoke it anytime.

**Instructions:** add_app_key, revoke_app_key, rotate_app_key

### username-registry -- Human-readable names

```
User wallet -> registerUsername("chaal") -> UsernameRecord PDA
                                             |-- username: "chaal"
                                             |-- tid: 9
                                             |-- expiry: 1 year
```

Maps `chaal.tribe` to TID 9. Annual renewal, transferable, releasable.

**Instructions:** register_username, renew_username, transfer_username, release_username

### social-graph -- Follow relationships

```
Direct:     User wallet -> follow()           -> Link PDA (33 bytes)
Delegated:  ER Server   -> follow_delegated() -> Link PDA (33 bytes)
```

Each follow creates a tiny PDA seeded `["link", follower_tid, following_tid]`. O(1) to create, O(1) to check, O(1) to delete. Unfollow closes the PDA and reclaims rent (~0.001 SOL back).

The delegated instructions (`follow_delegated`, `unfollow_delegated`, `init_profile_delegated`) accept a registered sequencer authority instead of the user's wallet. This is what enables the ER server.

**Instructions:** init_profile, follow, unfollow, init_sequencer, init_profile_delegated, follow_delegated, unfollow_delegated

---

## Layer 2: Hub (Off-Chain -- Message Storage + Indexing + Gossip)

### Why off-chain?

Storing tweet text on Solana would cost ~$0.01 per tweet and be slow. The hub stores messages in PostgreSQL for free and fast.

### How trust works without on-chain storage

```
1. User has app key registered on-chain (AppKeyRecord)

2. User signs tweet with app key:
   message_data -> blake3 hash -> ed25519 sign(hash, app_key_secret)

3. Submits to hub: { data, hash, signature, signer }

4. Hub validates:
   a. nacl.verify(hash, signature, signer)    <- cryptographic proof
   b. signer matches an active AppKeyRecord on-chain for this TID
   c. not a duplicate hash
   d. within rate limits

5. Stores in PostgreSQL
6. Gossips to peer hubs
```

The app key on-chain + signature off-chain bridge means: even though tweets are not on Solana, nobody can forge them. The on-chain key proves the signer was authorized by the TID owner.

### Indexing

The hub also subscribes to Solana program logs via WebSocket, parsing events like TidRegistered, Followed, and Unfollowed. This keeps a merged view of all registered TIDs, follow relationships, and tweets in PostgreSQL for fast read queries.

### Gossip Sync

Hubs sync messages with each other via a gossip protocol:
- Periodic `HAVE` messages broadcast hashes of recent messages
- Peers request missing hashes via `NEED`
- Full message sync via `GET` / `SYNC_MESSAGES`
- Automatic reconnection with exponential backoff

This makes the network censorship-resistant — if one hub goes down, others still have the data.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/submit` | Submit signed tweet/reaction |
| GET | `/v1/feed` | Global feed (newest first) |
| GET | `/v1/feed/:tid` | User's tweets |
| GET | `/v1/messages/:hash` | Single message by hash |
| GET | `/v1/replies?hash=` | Thread replies |
| GET | `/v1/channels` | Channel list |
| GET | `/v1/feed/channel/:id` | Channel feed |
| GET | `/v1/search?q=` | Text search |
| GET | `/v1/user/:tid` | User profile |
| GET | `/v1/users` | All users |
| GET | `/v1/followers/:tid` | Followers list |
| GET | `/v1/following/:tid` | Following list |
| GET | `/v1/peers` | Connected peers |
| GET | `/v1/sync/status` | Sync state per peer |
| POST | `/v1/upload` | Media uploads |
| GET | `/v1/media/:hash` | Serve media |

---

## Layer 3: ER Server (Ephemeral Rollup -- Fast Social Graph)

### The problem it solves

Every follow is a Solana transaction (~400ms, needs wallet approval popup). This feels slow for a social app.

### How it works

```
Step 1: User clicks "Follow"
  -> Frontend signs message: "tribe-er:follow:9:1:1775227154"
  -> Signs with wallet's signMessage() (no Solana tx, no popup on some wallets)
  -> Sends to ER server

Step 2: ER server (instant, < 50ms)
  -> Verifies ed25519 signature against custody wallet
  -> Checks custody_pubkey matches TID record on-chain (cached)
  -> Inserts into pending_operations (status: 'pending')
  -> Updates er_links (status: 'pending_follow')
  -> Updates er_profiles (increment counters)
  -> Returns { id: "1", status: "pending" }

Step 3: User sees "Following" immediately (optimistic)

Step 4: Settlement loop (every 10 seconds)
  -> Queries pending_operations WHERE status = 'pending'
  -> Checks if social profiles exist on-chain, creates missing ones
  -> Batches follow_delegated instructions (up to 4 per transaction)
  -> Signs with server wallet, sends to Solana
  -> On success: marks 'settled', stores tx_signature
  -> Link now exists on-chain permanently

Step 5: Hub picks up the Followed event via WebSocket
  -> Writes to hub's social_graph table
  -> Profile page shows updated follower counts
```

### The sequencer trust model

```
On-chain:  SequencerConfig PDA stores the ER server's pubkey
           follow_delegated checks: authority == sequencer_config.authority

Off-chain: ER server verifies user's custody signature before accepting ops
           Users can still use direct follow() on L1 to bypass the ER server
```

The ER server is a convenience layer, not a gatekeeper. If it goes down, users can follow directly on L1. When it is running, follows are instant.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/follow` | Submit follow (signed by custody wallet) |
| POST | `/v1/unfollow` | Submit unfollow (signed by custody wallet) |
| GET | `/v1/link/:followerTid/:followingTid` | Check follow status (includes pending) |
| GET | `/v1/profile/:tid` | Social profile (includes pending counts) |
| GET | `/health` | Server health + pending ops count |

---

## Layer 4: Frontend (tribe-app)

### How the pieces connect in the UI

```
Connect Wallet (Phantom)
    |
    |-- Check TID: getTidByCustody() -> reads CustodyLookup PDA on Solana
    |   |-- Not found? -> Registration flow
    |       |-- Step 1: registerTid()       -> Solana TX -> creates TidRecord
    |       |-- Step 2: registerUsername()   -> Solana TX -> creates UsernameRecord
    |       |-- Step 3: addAppKey()         -> Solana TX -> creates AppKeyRecord
    |                   stores nacl secret key in localStorage
    |
    |-- Post Tweet: TweetComposer
    |   |-- JSON.stringify(data) -> blake3 hash -> nacl.sign(hash, appKeySecret)
    |   |-- POST hub/v1/submit
    |
    |-- Follow User: FollowButton
    |   |-- "tribe-er:follow:9:1:timestamp" -> wallet.signMessage()
    |   |-- POST er-server/v1/follow (instant, no Solana TX)
    |
    |-- Read Feed: Feed component
    |   |-- GET hub/v1/feed
    |
    |-- View Profile: Profile page
        |-- GET hub/v1/user/:tid
        |-- GET hub/v1/followers/:tid
        |-- GET hub/v1/feed/:tid
```

### Pages

| Route | Description |
|-------|-------------|
| `/` | Home feed + tweet composer |
| `/explore` | User directory with follow buttons |
| `/channels` | Channel list + channel feeds |
| `/profile?tid=N` | User profile with tweets/followers/following tabs |
| `/tweet?hash=X` | Thread view with replies |
| `/search?q=X` | Search results |

---

## Complete Flow: Follow + Tweet Cycle

```
1. Alice (TID 9) clicks Follow on Bob (TID 1)

2. Frontend: wallet.signMessage("tribe-er:follow:9:1:1775227154")
   -> POST er-server/v1/follow { followerTid: "9", followingTid: "1", ... }

3. ER Server:
   -> Verifies signature
   -> Checks custodyPubkey == TID 9's custody on-chain
   -> INSERT pending_operations (follow, 9, 1, pending)
   -> Returns { id: "1", status: "pending" }

4. Frontend shows "Following" (instant)

5. [10 seconds later] ER settlement loop:
   -> Checks: TID 9 social profile exists? No -> init_profile_delegated(9)
   -> Builds follow_delegated(9, 1) instruction
   -> Signs with server wallet -> sendAndConfirmTransaction
   -> Solana creates Link PDA on-chain
   -> Program emits Followed { follower_tid: 9, following_tid: 1 }

6. Hub (Solana WebSocket listener):
   -> Receives Followed event
   -> INSERT social_graph (9, 1)

7. Alice posts "Hello from Alice!"
   -> blake3(JSON.stringify({ type: 1, tid: 9, body: { text: "Hello..." } }))
   -> nacl.sign(hash, appKeySecret)
   -> POST hub/v1/submit
   -> Hub: verify signature, check app key on-chain, store in PostgreSQL
   -> Hub gossips the message to peer hubs

8. Bob opens his feed:
   -> GET hub/v1/feed
   -> Returns Alice's tweet with username "alice.tribe"
   -> Bob sees the tweet with a heart button and reply link
```

---

## What's On-Chain vs Off-Chain

| Data | Where | Why |
|------|-------|-----|
| TID identity | On-chain | Ownership cannot be revoked |
| App keys | On-chain | Delegation must be verifiable |
| Usernames | On-chain | Uniqueness must be enforced |
| Follow links | On-chain (via ER) | Social graph is a public good |
| Social profile counters | On-chain | Follower counts are trustworthy |
| Sequencer config | On-chain | ER authority must be verifiable |
| Tweet content | Off-chain (hub) | Too expensive/slow for L1 |
| Tweet signatures | Off-chain (hub) | Verified against on-chain app keys |
| Indexed state | Off-chain (hub) | Aggregation for fast reads |
| Pending follows | Off-chain (ER server) | Optimistic state before L1 settlement |

---

## How Mainnet Migration Works

The architecture is the same -- just change config:

1. Deploy programs to mainnet (new program IDs)
2. Update SDK `MAINNET_CONFIG` with new IDs + production URLs
3. Deploy hub, ER server to production VPS
4. Point frontend env vars at production URLs
5. Fund ER server wallet with mainnet SOL
6. Register sequencer on mainnet

No code changes needed. The separation of concerns means each piece is independently deployable.

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| On-chain programs | Rust, Anchor 0.31.1 |
| SDK | TypeScript, @coral-xyz/anchor, @solana/web3.js |
| Hub | Fastify, PostgreSQL 16, tweetnacl, blake3 |
| ER server | Fastify, PostgreSQL 16, tweetnacl |
| Frontend | Next.js 16, React 19, Tailwind CSS 4, Solana wallet adapter |
| Blockchain | Solana (devnet, mainnet-compatible) |
