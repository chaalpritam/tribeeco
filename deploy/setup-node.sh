#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       TribeEco — Node Setup                  ║${NC}"
echo -e "${CYAN}║   Set up this Mac as a TribeEco node         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Load config ──────────────────────────────────────────────────
if [ ! -f "$SCRIPT_DIR/.env.node" ]; then
  echo -e "${YELLOW}No .env.node found. Creating from template...${NC}"
  cp "$SCRIPT_DIR/.env.node.example" "$SCRIPT_DIR/.env.node"
  echo ""
  echo -e "${YELLOW}Please edit deploy/.env.node with your settings, then re-run this script.${NC}"
  echo "  Key values to set:"
  echo "    HUB_ID         — unique name for this node (e.g., hub-air, hub-mini)"
  echo "    PEER_HUB_URL   — the other node's gossip URL (e.g., wss://hub-b.yourdomain.com/gossip)"
  echo "    DOMAIN          — your domain (e.g., tribe.example.com)"
  echo "    NODE_PREFIX     — subdomain prefix for this node (e.g., hub-a or hub-b)"
  exit 0
fi

source "$SCRIPT_DIR/.env.node"

# ── Step 1: Check prerequisites ──────────────────────────────────
echo "==> [1/7] Checking prerequisites..."

MISSING=0

if ! command -v docker &>/dev/null; then
  fail "Docker not installed. Install: https://docs.docker.com/get-docker/"
  MISSING=1
else
  ok "Docker found"
fi

if ! command -v node &>/dev/null; then
  fail "Node.js not installed. Install: https://nodejs.org/"
  MISSING=1
else
  ok "Node.js found ($(node --version))"
fi

if ! command -v pnpm &>/dev/null; then
  fail "pnpm not installed. Install: npm install -g pnpm"
  MISSING=1
else
  ok "pnpm found"
fi

if ! command -v cloudflared &>/dev/null; then
  warn "cloudflared not installed. Installing via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install cloudflared
    ok "cloudflared installed"
  else
    fail "Homebrew not found. Install cloudflared manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    MISSING=1
  fi
else
  ok "cloudflared found"
fi

if [ "$MISSING" -ne 0 ]; then
  echo -e "${RED}==> Fix missing prerequisites and re-run.${NC}"
  exit 1
fi

# ── Step 2: Start Postgres containers ────────────────────────────
echo ""
echo "==> [2/7] Starting PostgreSQL containers..."

# Make sure Docker daemon is running
if ! docker info &>/dev/null 2>&1; then
  if command -v colima &>/dev/null; then
    warn "Docker daemon not running. Starting Colima..."
    colima start
  else
    fail "Docker daemon not running. Start Docker Desktop or Colima."
    exit 1
  fi
fi

docker compose -f "$SCRIPT_DIR/docker-compose.node.yml" up -d

# Wait for DBs
for i in $(seq 1 20); do
  if docker compose -f "$SCRIPT_DIR/docker-compose.node.yml" ps --format json 2>/dev/null | grep -q "healthy"; then
    break
  fi
  sleep 1
done
ok "PostgreSQL containers running (hub-db:5436, er-db:5435)"

# ── Step 3: Install dependencies ─────────────────────────────────
echo ""
echo "==> [3/7] Installing dependencies..."

(cd "$ROOT_DIR/tribe-hub" && pnpm install --silent)
ok "tribe-hub dependencies installed"

(cd "$ROOT_DIR/tribe-er-server" && pnpm install --silent)
ok "tribe-er-server dependencies installed"

# ── Step 4: Generate service .env files ──────────────────────────
echo ""
echo "==> [4/7] Generating .env files..."

cat > "$ROOT_DIR/tribe-hub/.env" <<HUBEOF
PORT=4000
HUB_ID=${HUB_ID}
SOLANA_RPC_URL=${SOLANA_RPC_URL}
SOLANA_WS_URL=${SOLANA_WS_URL}
DATABASE_URL=${HUB_DATABASE_URL}
PEERS=${PEER_HUB_URL}
GOSSIP_INTERVAL_MS=5000
MAX_SYNC_BATCH_SIZE=100
MEDIA_DIR=./data/media
TID_REGISTRY_PROGRAM_ID=${TID_REGISTRY_PROGRAM_ID}
APP_KEY_REGISTRY_PROGRAM_ID=${APP_KEY_REGISTRY_PROGRAM_ID}
SOCIAL_GRAPH_PROGRAM_ID=${SOCIAL_GRAPH_PROGRAM_ID}
HUBEOF
ok "tribe-hub/.env written"

cat > "$ROOT_DIR/tribe-er-server/.env" <<EREOF
PORT=3003
SOLANA_RPC_URL=${SOLANA_RPC_URL}
DATABASE_URL=${ER_DATABASE_URL}
SERVER_WALLET_PATH=${SERVER_WALLET_PATH}
SETTLEMENT_INTERVAL_MS=${SETTLEMENT_INTERVAL_MS}
SOCIAL_GRAPH_PROGRAM_ID=${SOCIAL_GRAPH_PROGRAM_ID}
TID_REGISTRY_PROGRAM_ID=${TID_REGISTRY_PROGRAM_ID}
EREOF
ok "tribe-er-server/.env written"

# ── Step 5: Check server wallet ──────────────────────────────────
echo ""
echo "==> [5/7] Checking server wallet..."

WALLET_PATH="$ROOT_DIR/tribe-er-server/${SERVER_WALLET_PATH}"
if [ -f "$WALLET_PATH" ]; then
  ok "Server wallet found at $WALLET_PATH"
else
  fail "Server wallet not found at $WALLET_PATH"
  echo "    Copy the same server-wallet.json to both nodes."
  echo "    This is the ER sequencer's Solana keypair."
  exit 1
fi

# ── Step 6: Cloudflare Tunnel ────────────────────────────────────
echo ""
echo "==> [6/7] Cloudflare Tunnel setup..."

TUNNEL_NAME="tribe-${NODE_PREFIX}"

# Check if tunnel already exists
if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  ok "Tunnel '$TUNNEL_NAME' already exists"
else
  warn "Creating tunnel '$TUNNEL_NAME'..."
  echo ""
  echo -e "${YELLOW}  You need to authenticate cloudflared first (one-time):${NC}"
  echo "    cloudflared tunnel login"
  echo ""
  echo "  Then create the tunnel:"
  echo "    cloudflared tunnel create $TUNNEL_NAME"
  echo ""
  echo "  Then add DNS routes:"
  echo "    cloudflared tunnel route dns $TUNNEL_NAME ${NODE_PREFIX}.${DOMAIN}"
  echo "    cloudflared tunnel route dns $TUNNEL_NAME er-${NODE_PREFIX#hub-}.${DOMAIN}"
  echo ""
  echo "  After that, re-run this script."
  exit 0
fi

# Generate tunnel config
TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

cat > "$ROOT_DIR/deploy/cloudflare-tunnel-${NODE_PREFIX}.yml" <<CFEOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}

ingress:
  - hostname: ${NODE_PREFIX}.${DOMAIN}
    service: http://localhost:4000
  - hostname: er-${NODE_PREFIX#hub-}.${DOMAIN}
    service: http://localhost:3003
  - service: http_status:404
CFEOF
ok "Tunnel config written to deploy/cloudflare-tunnel-${NODE_PREFIX}.yml"

# ── Step 7: Create launchd plists ────────────────────────────────
echo ""
echo "==> [7/7] Creating launchd service files..."

PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR"

# Hub plist
cat > "$PLIST_DIR/com.tribe.hub.plist" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tribe.hub</string>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}/tribe-hub</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which pnpm)</string>
    <string>run</string>
    <string>start</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${ROOT_DIR}/.logs/hub.log</string>
  <key>StandardErrorPath</key>
  <string>${ROOT_DIR}/.logs/hub.error.log</string>
</dict>
</plist>
PEOF
ok "com.tribe.hub.plist created"

# ER server plist
cat > "$PLIST_DIR/com.tribe.er-server.plist" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tribe.er-server</string>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}/tribe-er-server</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which pnpm)</string>
    <string>run</string>
    <string>start</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${ROOT_DIR}/.logs/er-server.log</string>
  <key>StandardErrorPath</key>
  <string>${ROOT_DIR}/.logs/er-server.error.log</string>
</dict>
</plist>
PEOF
ok "com.tribe.er-server.plist created"

# Cloudflared plist
cat > "$PLIST_DIR/com.tribe.cloudflared.plist" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tribe.cloudflared</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which cloudflared)</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>${ROOT_DIR}/deploy/cloudflare-tunnel-${NODE_PREFIX}.yml</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${ROOT_DIR}/.logs/cloudflared.log</string>
  <key>StandardErrorPath</key>
  <string>${ROOT_DIR}/.logs/cloudflared.error.log</string>
</dict>
</plist>
PEOF
ok "com.tribe.cloudflared.plist created"

mkdir -p "$ROOT_DIR/.logs"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Node setup complete!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  To start all services now:"
echo ""
echo "    launchctl load ~/Library/LaunchAgents/com.tribe.hub.plist"
echo "    launchctl load ~/Library/LaunchAgents/com.tribe.er-server.plist"
echo "    launchctl load ~/Library/LaunchAgents/com.tribe.cloudflared.plist"
echo ""
echo "  Services will auto-start on boot."
echo ""
echo "  To stop:"
echo ""
echo "    launchctl unload ~/Library/LaunchAgents/com.tribe.hub.plist"
echo "    launchctl unload ~/Library/LaunchAgents/com.tribe.er-server.plist"
echo "    launchctl unload ~/Library/LaunchAgents/com.tribe.cloudflared.plist"
echo ""
echo "  Logs: $ROOT_DIR/.logs/"
echo ""
echo "  Vercel env vars to set:"
echo "    NEXT_PUBLIC_HUB_URLS=https://hub-a.${DOMAIN},https://hub-b.${DOMAIN}"
echo "    NEXT_PUBLIC_ER_SERVER_URLS=https://er-a.${DOMAIN},https://er-b.${DOMAIN}"
echo ""
