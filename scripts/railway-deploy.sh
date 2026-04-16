#!/bin/bash
#
# Deploy TribeEco to Railway
#
# Prerequisites:
#   brew install railway
#   railway login
#
# Usage:
#   ./scripts/railway-deploy.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco — Railway Deployment            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Check railway CLI
if ! command -v railway &>/dev/null; then
  fail "Railway CLI not found. Install with: brew install railway"
  exit 1
fi
ok "Railway CLI found"

# Check login
if ! railway whoami &>/dev/null 2>&1; then
  fail "Not logged in. Run: railway login"
  exit 1
fi
ok "Logged in as $(railway whoami 2>/dev/null)"

# Check for wallet
WALLET_FILE="$PROJECT_DIR/tribe-er-server/server-wallet.json"
PERSISTENT_WALLET="$HOME/.tribe/server-wallet.json"
if [ -f "$WALLET_FILE" ]; then
  WALLET_B64=$(base64 < "$WALLET_FILE")
  ok "Server wallet found"
elif [ -f "$PERSISTENT_WALLET" ]; then
  WALLET_B64=$(base64 < "$PERSISTENT_WALLET")
  ok "Server wallet found (from ~/.tribe/)"
else
  fail "No server wallet found. Run 'tribe doctor' first to generate one."
  exit 1
fi

echo ""
echo -e "${BOLD}This will create a Railway project with 5 services:${NC}"
echo "  1. er-db        (Postgres)"
echo "  2. hub-db       (Postgres)"
echo "  3. er-server    (Docker)"
echo "  4. hub          (Docker)"
echo "  5. tribe-app    (Docker)"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "==> Creating Railway project..."
railway init --name tribeeco 2>/dev/null || true
ok "Project initialized"

# --- ER Database ---
echo ""
echo "[1/5] Creating ER database..."
railway service create er-db 2>/dev/null || true
railway service set er-db
railway add --plugin postgresql
info "ER database created (Railway managed Postgres)"

# --- Hub Database ---
echo "[2/5] Creating Hub database..."
railway service create hub-db 2>/dev/null || true
railway service set hub-db
railway add --plugin postgresql
info "Hub database created (Railway managed Postgres)"

# --- ER Server ---
echo "[3/5] Deploying ER server..."
railway service create er-server 2>/dev/null || true
railway service set er-server
railway variables set \
  PORT=3003 \
  SOLANA_RPC_URL=https://api.devnet.solana.com \
  SERVER_WALLET_PATH=/app/server-wallet.json \
  SERVER_WALLET_JSON="$WALLET_B64" \
  SETTLEMENT_INTERVAL_MS=10000 \
  SOCIAL_GRAPH_PROGRAM_ID=8kKnWvbmTjWq5uPePk79RRbQMAXCszNFzHdRwUS4N74w \
  TID_REGISTRY_PROGRAM_ID=4BSmJmRGQWKgioP9DG2bUuRS9U3V6soRauU7Nv6yGvHD
info "ER server configured — link DATABASE_URL to er-db in Railway dashboard"

# --- Hub ---
echo "[4/5] Deploying Hub..."
railway service create hub 2>/dev/null || true
railway service set hub
railway variables set \
  PORT=4000 \
  HUB_ID=hub-primary \
  SOLANA_RPC_URL=https://api.devnet.solana.com \
  SOLANA_WS_URL=wss://api.devnet.solana.com \
  MEDIA_DIR=/app/data/media \
  TID_REGISTRY_PROGRAM_ID=4BSmJmRGQWKgioP9DG2bUuRS9U3V6soRauU7Nv6yGvHD \
  APP_KEY_REGISTRY_PROGRAM_ID=5LtbFUeAoXWRovGpyWnRJhiCS62XsTYKVErT9kPpv4hN \
  SOCIAL_GRAPH_PROGRAM_ID=8kKnWvbmTjWq5uPePk79RRbQMAXCszNFzHdRwUS4N74w \
  GOSSIP_INTERVAL_MS=5000 \
  MAX_SYNC_BATCH_SIZE=100
info "Hub configured — link DATABASE_URL to hub-db in Railway dashboard"

# --- Frontend ---
echo "[5/5] Deploying Frontend app..."
railway service create tribe-app 2>/dev/null || true
railway service set tribe-app
railway variables set PORT=3002
info "Frontend configured"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Railway project created!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  1. Open Railway dashboard:"
echo -e "     ${CYAN}railway open${NC}"
echo ""
echo "  2. For each backend service (er-server, hub), link the DATABASE_URL"
echo "     to the corresponding Postgres plugin in the Railway dashboard."
echo ""
echo "  3. Set the root directory for each service in Railway dashboard:"
echo "     - er-server  → tribe-er-server"
echo "     - hub        → tribe-hub"
echo "     - tribe-app  → tribe-app"
echo ""
echo "  4. Deploy all services:"
echo -e "     ${CYAN}railway up${NC}"
echo ""
echo "  5. Generate public domains in Railway dashboard for:"
echo "     - tribe-app  (frontend)"
echo "     - hub        (API)"
echo "     - er-server  (RPC)"
echo ""
echo "  Once deployed, your public endpoints will be:"
echo -e "    ${CYAN}Frontend:${NC}   https://tribe-app-production.up.railway.app"
echo -e "    ${CYAN}Hub API:${NC}    https://hub-production.up.railway.app"
echo -e "    ${CYAN}ER Server:${NC}  https://er-server-production.up.railway.app"
echo ""
