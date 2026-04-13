# Tribe Protocol — Developer Guide

Build decentralized social apps on the Tribe protocol. This guide covers everything you need to integrate with Tribe — from registering identities to running your own hub.

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture Overview](#architecture-overview)
- [SDK Reference](#sdk-reference)
- [On-Chain Programs](#on-chain-programs)
- [Running a Hub](#running-a-hub)
- [Message Format](#message-format)
- [API Reference](#api-reference)
- [Ephemeral Rollup](#ephemeral-rollup)
- [Examples](#examples)

---

## Quick Start

### Install the SDK

```bash
npm install @tribe-protocol/sdk
```

### Connect and register

```typescript
import { TribeClient } from "@tribe-protocol/sdk";
import { AnchorProvider } from "@coral-xyz/anchor";

// Connect to devnet
const provider = new AnchorProvider(connection, wallet, { commitment: "confirmed" });
const tribe = TribeClient.forDevnet(provider);

// Register a Tribe ID
const { tid, txSig } = await tribe.identity.tid.register(recoveryAddress);

// Add an app key for signing messages
await tribe.identity.appKeys.addAppKey(tid, appPubkey, AppKeyScope.Full);

// Register a username
await tribe.identity.usernames.register(tid, "alice");

// Follow someone
await tribe.social.follow(myTid, targetTid);

// Publish a tweet
await tribe.tweets.publish(tid, "Hello Tribe!", signingKey);
```

### Connect to a hub

```typescript
// Your app talks to a hub for off-chain data (tweets, feed, search)
const HUB_URL = "http://localhost:4000";

// Get the global feed
const res = await fetch(`${HUB_URL}/v1/feed`);
const { tweets } = await res.json();

// Submit a signed message
await fetch(`${HUB_URL}/v1/submit`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(signedMessage),
});
```

---

## Architecture Overview

```
Your App
    |
    |-- SDK (identity, social graph, tweets)
    |       |
    |       |-- On-chain: tid-registry, app-key-registry, username-registry, social-graph, hub-registry
    |       |-- Off-chain: tribe-hub (message storage + gossip sync)
    |
    |-- Hub API (REST + WebSocket)
            |-- /v1/submit (post messages)
            |-- /v1/feed (read feed)
            |-- /v1/user/:tid (user profiles)
            |-- /v1/ws (real-time updates)
```

### What's on-chain

| Data | Program | Why on-chain |
|------|---------|-------------|
| Identity (TID) | tid-registry | Ownership cannot be revoked |
| App signing keys | app-key-registry | Delegation must be verifiable |
| Usernames (.tribe) | username-registry | Uniqueness must be enforced |
| Follow relationships | social-graph | Social graph is a public good |
| Hub directory | hub-registry | Hub discovery must be trustless |

### What's off-chain (on hubs)

| Data | Where | Why off-chain |
|------|-------|--------------|
| Tweet content | Hub PostgreSQL | Too expensive for L1 |
| Reactions/likes | Hub PostgreSQL | High frequency, low value |
| Search index | Hub PostgreSQL | Aggregation for fast reads |
| DMs (encrypted) | Hub PostgreSQL | End-to-end encrypted, hubs store ciphertext |

---

## SDK Reference

### TribeClient

The main entry point. Create one per user session.

```typescript
// Factory methods
const tribe = TribeClient.forDevnet(provider);
const tribe = TribeClient.forMainnet(provider);
const tribe = TribeClient.forNetwork(provider, customConfig);

// With Ephemeral Rollup for instant follows
const tribe = TribeClient.forDevnet(provider, {
  execution: new EphemeralRollupProvider({
    erServerUrl: "http://localhost:3003",
    custodyPubkey: wallet.publicKey.toBase58(),
    signFn: (msg) => wallet.signMessage(msg),
  }),
});
```

### Identity

```typescript
// TID (Tribe ID)
const { tid, txSig } = await tribe.identity.tid.register(recoveryAddress);
const record = await tribe.identity.tid.getTid(tid);            // { tid, custodyAddress, recoveryAddress }
const tid = await tribe.identity.tid.getTidByCustody(walletPubkey); // bigint | null
await tribe.identity.tid.transfer(tid, newCustody);
await tribe.identity.tid.recover(tid, newCustody);
await tribe.identity.tid.changeRecovery(tid, newRecovery);

// App Keys
await tribe.identity.appKeys.addAppKey(tid, appPubkey, AppKeyScope.Full, expiresAt);
await tribe.identity.appKeys.revokeAppKey(tid, appPubkey);
await tribe.identity.appKeys.rotateAppKey(tid, oldKey, newKey, scope, expiresAt);
const key = await tribe.identity.appKeys.getAppKey(tid, appPubkey);

// Scopes: Full (0), TweetsOnly (1), SocialOnly (2), ReadOnly (3)

// Usernames
await tribe.identity.usernames.register(tid, "alice");
await tribe.identity.usernames.renew(tid, "alice");
await tribe.identity.usernames.transfer("alice", newTid);
await tribe.identity.usernames.release(tid, "alice");
const record = await tribe.identity.usernames.getUsername("alice");
```

### Social Graph

```typescript
await tribe.social.follow(myTid, targetTid);
await tribe.social.unfollow(myTid, targetTid);
const isFollowing = await tribe.social.isFollowing(myTid, targetTid);
const profile = await tribe.social.getProfile(tid);
// { tid, followingCount, followersCount }
```

### Tweets

```typescript
// Publish (requires app key secret)
const hash = await tribe.tweets.publish(tid, "Hello!", signingKey, {
  mentions: [otherTid],
  embeds: ["https://example.com/image.png"],
  parentHash: parentTweetHash,   // for replies
  channelId: "general",          // for channels
});

// Query
const page = await tribe.tweets.getTweetsByTid(tid, 20, cursor);
const tweet = await tribe.tweets.getTweet(hash);
```

### Message Signing

```typescript
import { signMessage, verifyMessage, MessageType, Network } from "@tribe-protocol/sdk";

const data = {
  type: MessageType.TWEET_ADD,
  tid: 9n,
  timestamp: Math.floor(Date.now() / 1000),
  network: Network.DEVNET,
  body: { text: "Hello!", mentions: [], embeds: [] },
};

const message = signMessage(data, signingKey);  // { protocolVersion, data, hash, signature, signer }
const valid = verifyMessage(message);            // true/false
```

---

## On-Chain Programs

### Program IDs (Devnet)

```
tid-registry:      4BSmJmRGQWKgioP9DG2bUuRS9U3V6soRauU7Nv6yGvHD
app-key-registry:  5LtbFUeAoXWRovGpyWnRJhiCS62XsTYKVErT9kPpv4hN
username-registry: 65oKjSjcGYR61ASzDYczbodz6H8TARtJyQGvb5V9y9W1
social-graph:      8kKnWvbmTjWq5uPePk79RRbQMAXCszNFzHdRwUS4N74w
hub-registry:      (deploy after build)
```

### PDA Seeds

```
TidRecord:       ["tid", tid_le_bytes(8)]
CustodyLookup:   ["custody", custody_pubkey(32)]
AppKeyRecord:    ["app_key", tid_le_bytes(8), app_pubkey(32)]
UsernameRecord:  ["username", username_utf8_bytes]
TidUsername:     ["tid_username", tid_le_bytes(8)]
SocialProfile:   ["social_profile", tid_le_bytes(8)]
Link:            ["link", follower_tid_le_bytes(8), following_tid_le_bytes(8)]
SequencerConfig: ["sequencer_config"]
HubRecord:       ["hub", operator_pubkey(32)]
```

### Account Layouts

```
TidRecord (89 bytes):
  8  discriminator
  8  tid (u64 LE)
  32 custody_address (Pubkey)
  32 recovery_address (Pubkey)
  8  registered_at (i64 LE)
  1  bump

AppKeyRecord (67 bytes):
  8  discriminator
  8  tid (u64 LE)
  32 app_pubkey (Pubkey)
  1  scope (u8: 0=Full, 1=TweetsOnly, 2=SocialOnly, 3=ReadOnly)
  8  created_at (i64 LE)
  8  expires_at (i64 LE, 0=never)
  1  revoked (bool)
  1  bump

SocialProfile (25 bytes):
  8  discriminator
  8  tid (u64 LE)
  4  following_count (u32 LE)
  4  followers_count (u32 LE)
  1  bump

Link (33 bytes):
  8  discriminator
  8  follower_tid (u64 LE)
  8  following_tid (u64 LE)
  8  created_at (i64 LE)
  1  bump
```

---

## Running a Hub

### What is a Hub?

A hub is a node on the Tribe network that:
- Stores tweets (signed messages) in PostgreSQL
- Indexes on-chain events (TID registrations, follows)
- Syncs messages with other hubs via gossip
- Serves a REST API for apps to read/write data

Anyone can run a hub. Hubs sync with each other — if one goes down, others still have the data.

### Start a Hub

```bash
cd tribe-hub
cp .env.example .env
# Edit .env with your config

docker-compose up -d   # Start PostgreSQL
pnpm install
pnpm run dev           # Start the hub on port 4000
```

### Connect to Peers

Set the `PEERS` environment variable to connect to other hubs:

```env
PEERS=ws://hub1.tribe.protocol/gossip,ws://hub2.tribe.protocol/gossip
```

Hubs automatically sync messages via the gossip protocol.

### Register Your Hub On-Chain

```typescript
// Register so apps can discover your hub
await hubRegistry.registerHub(
  "https://my-hub.example.com",
  gossipKeypair.publicKey
);

// Send periodic heartbeats to prove liveness
setInterval(() => hubRegistry.heartbeat(), 60 * 60 * 1000); // hourly
```

### Hub API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/submit` | Submit a signed message |
| GET | `/v1/feed` | Global feed (all tweets) |
| GET | `/v1/feed/:tid` | User's tweet feed |
| GET | `/v1/feed/channel/:id` | Channel feed |
| GET | `/v1/messages/:hash` | Single message |
| GET | `/v1/search?q=` | Search tweets |
| GET | `/v1/replies?hash=` | Thread replies |
| GET | `/v1/user/:tid` | User profile |
| GET | `/v1/users` | All users |
| GET | `/v1/followers/:tid` | Followers list |
| GET | `/v1/following/:tid` | Following list |
| GET | `/v1/peers` | Connected peers |
| GET | `/v1/sync/status` | Sync state per peer |
| GET | `/health` | Hub health |
| WS | `/gossip` | Gossip peer connection |

---

## Message Format

Every tweet is a self-authenticating signed message:

```typescript
{
  protocolVersion: 1,
  data: {
    type: 1,              // TWEET_ADD
    tid: 9,               // author's Tribe ID
    timestamp: 1775200000, // unix seconds
    network: 2,           // DEVNET
    body: {
      text: "Hello Tribe!",
      mentions: [],        // TIDs of mentioned users
      embeds: [],          // URLs (images, links)
      parent_hash: null,   // reply-to hash
      channel_id: null,    // channel name
    }
  },
  hash: "base64...",      // BLAKE3 hash of encoded data
  signature: "base64...", // ed25519 signature over hash
  signer: "base64...",    // ed25519 public key (must be registered on-chain)
}
```

### Message Types

| Type | Value | Description |
|------|-------|-------------|
| TWEET_ADD | 1 | Post a new tweet |
| TWEET_REMOVE | 2 | Delete a tweet |
| REACTION_ADD | 3 | Like or recast |
| REACTION_REMOVE | 4 | Remove a reaction |
| LINK_ADD | 5 | Follow (reserved) |
| LINK_REMOVE | 6 | Unfollow (reserved) |
| USER_DATA_ADD | 7 | Profile update |
| USERNAME_PROOF | 8 | Username claim |
| CHANNEL_ADD | 9 | Create channel |
| CHANNEL_JOIN | 10 | Join channel |
| CHANNEL_LEAVE | 11 | Leave channel |

### Verification

Any hub verifies messages by:

1. `nacl.sign.detached.verify(hash, signature, signer)` — cryptographic proof
2. Look up `signer` on Solana — must be a registered `AppKeyRecord` for the `tid`
3. Check app key is not revoked and not expired
4. Check for duplicate hash

If all pass, the message is authentic and can be stored + gossiped.

---

## Ephemeral Rollup

For instant social graph operations without waiting for Solana L1 (~400ms):

```typescript
import { EphemeralRollupProvider } from "@tribe-protocol/sdk";

const tribe = TribeClient.forDevnet(provider, {
  execution: new EphemeralRollupProvider({
    erServerUrl: "http://localhost:3003",
    custodyPubkey: wallet.publicKey.toBase58(),
    signFn: (msg) => wallet.signMessage(msg),
  }),
});

// This is instant (~50ms) — settles to L1 every 10 seconds
await tribe.social.follow(myTid, targetTid);
```

The ER server:
1. Accepts signed follow/unfollow requests
2. Validates custody wallet signature
3. Updates local state immediately (optimistic)
4. Batches operations and settles to Solana L1 every 10 seconds
5. Auto-initializes social profiles as needed

---

## Examples

### Build a Twitter-like app

```typescript
// 1. User connects wallet
const provider = new AnchorProvider(connection, wallet, opts);
const tribe = TribeClient.forDevnet(provider);

// 2. Check if user has a TID
const tid = await tribe.identity.tid.getTidByCustody(wallet.publicKey);

// 3. If not, register
if (!tid) {
  const { tid: newTid } = await tribe.identity.tid.register(wallet.publicKey);
  await tribe.identity.usernames.register(newTid, "alice");
  // Generate app key for signing tweets
  const keypair = nacl.sign.keyPair();
  await tribe.identity.appKeys.addAppKey(newTid, keypair.publicKey, 0);
  // Store keypair.secretKey securely
}

// 4. Post a tweet
await tribe.tweets.publish(tid, "My first tweet!", signingKeySecret);

// 5. Read the feed
const feed = await tribe.tweets.getTweetsByTid(tid);
```

### Build a follower bot

```typescript
// Follow everyone who follows you
const profile = await tribe.social.getProfile(myTid);
const followers = await fetch(`${HUB_URL}/v1/followers/${myTid}`).then(r => r.json());

for (const f of followers.followers) {
  const isFollowing = await tribe.social.isFollowing(myTid, BigInt(f.follower_tid));
  if (!isFollowing) {
    await tribe.social.follow(myTid, BigInt(f.follower_tid));
  }
}
```

### Build a channel-based community

```typescript
// Post to a channel
await tribe.tweets.publish(tid, "Welcome to #solana-devs!", signingKey, {
  channelId: "solana-devs",
});

// Read channel feed
const feed = await fetch(`${HUB_URL}/v1/feed/channel/solana-devs`).then(r => r.json());
```

### Run your own hub

```bash
# Clone and start
git clone https://github.com/your-org/tribe-hub
cd tribe-hub
cp .env.example .env
echo "PEERS=ws://seed1.tribe.protocol/gossip" >> .env
docker-compose up -d && pnpm install && pnpm run dev

# Your hub is now syncing with the network
# Point your app at http://localhost:4000
```

---

## Network Configuration

### Devnet

```typescript
{
  cluster: "devnet",
  rpcUrl: "https://api.devnet.solana.com",
  programIds: {
    tidRegistry: "4BSmJmRGQWKgioP9DG2bUuRS9U3V6soRauU7Nv6yGvHD",
    appKeyRegistry: "5LtbFUeAoXWRovGpyWnRJhiCS62XsTYKVErT9kPpv4hN",
    usernameRegistry: "65oKjSjcGYR61ASzDYczbodz6H8TARtJyQGvb5V9y9W1",
    socialGraph: "8kKnWvbmTjWq5uPePk79RRbQMAXCszNFzHdRwUS4N74w",
  },
  hubUrl: "http://localhost:4000",
  erServerUrl: "http://localhost:3003",
}
```

### Mainnet

Update program IDs after mainnet deployment. All other configuration is the same — just change URLs and cluster.

---

## Contributing

The protocol is open source. To contribute:

1. Fork the relevant repo
2. Make changes
3. Run tests (`pnpm test`)
4. Submit a PR

### Repo Structure

```
TribeEco/
├── tribe-protocol/     # Solana programs (Rust/Anchor)
├── tribe-sdk/          # TypeScript SDK
├── tribe-hub/          # Decentralized hub (gossip + storage + indexing)
├── tribe-er-server/    # Ephemeral Rollup sequencer
└── tribe-app/          # Next.js demo frontend
```
