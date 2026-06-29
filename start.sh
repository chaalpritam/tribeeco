#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT_DIR/.logs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

MISSING=0

# ── Prerequisite checks ──────────────────────────────────────────────

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          TribeEco - Starting Up              ║${NC}"
echo -e "${CYAN}║   Decentralized Social Protocol on Solana    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "==> Checking prerequisites..."

# 1. Docker CLI
if ! command -v docker &>/dev/null; then
  fail "docker is not installed. Install Docker: https://docs.docker.com/get-docker/"
  MISSING=1
else
  ok "docker found ($(docker --version | head -1))"
fi

# 2. Docker Compose
if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
  fail "docker-compose is not installed. Install it: https://docs.docker.com/compose/install/"
  MISSING=1
else
  ok "docker-compose found"
fi

# 3. Docker daemon running (auto-start Colima if available)
if ! docker info &>/dev/null 2>&1; then
  if command -v colima &>/dev/null; then
    warn "Docker daemon not running. Starting Colima..."
    colima start
    if ! docker info &>/dev/null 2>&1; then
      fail "Colima started but Docker daemon still unreachable."
      MISSING=1
    else
      ok "Colima started successfully"
    fi
  else
    fail "Docker daemon is not running. Start Docker Desktop or run 'colima start'."
    MISSING=1
  fi
else
  ok "Docker daemon is running"
fi

# 4. Node.js
if ! command -v node &>/dev/null; then
  fail "node is not installed. Install Node.js: https://nodejs.org/"
  MISSING=1
else
  ok "node found ($(node --version))"
fi

# 5. pnpm
if ! command -v pnpm &>/dev/null; then
  fail "pnpm is not installed. Install it: npm install -g pnpm"
  MISSING=1
else
  ok "pnpm found ($(pnpm --version))"
fi

# 6. node_modules for tribe-twitter-app
if [ ! -d "$ROOT_DIR/tribe-twitter-app/node_modules" ]; then
  warn "tribe-twitter-app dependencies not installed. Running 'pnpm install'..."
  (cd "$ROOT_DIR/tribe-twitter-app" && pnpm install)
  if [ $? -ne 0 ]; then
    fail "pnpm install failed for tribe-twitter-app."
    MISSING=1
  else
    ok "tribe-twitter-app dependencies installed"
  fi
else
  ok "tribe-twitter-app dependencies present"
fi

# 7. Required build directories
for svc in tribe-er-server tribe-hub; do
  if [ ! -d "$ROOT_DIR/$svc" ]; then
    fail "Directory '$svc' not found. Make sure you have the full repo."
    MISSING=1
  else
    ok "$svc directory present"
  fi
done

# 8. ER server wallet file
if [ ! -f "$ROOT_DIR/tribe-er-server/server-wallet.json" ]; then
  fail "tribe-er-server/server-wallet.json not found. This is required by the ER server."
  MISSING=1
else
  ok "ER server wallet file present"
fi

# 9. Ports availability check
for entry in "3002:frontend" "3003:er-server" "4000:hub" "5435:er-db" "5436:hub-db"; do
  PORT="${entry%%:*}"
  NAME="${entry##*:}"
  if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
    warn "Port $PORT ($NAME) is already in use. This may cause conflicts."
  else
    ok "Port $PORT ($NAME) is available"
  fi
done

echo ""

# ── Abort if anything critical is missing ─────────────────────────────

if [ "$MISSING" -ne 0 ]; then
  echo -e "${RED}==> Some prerequisites are missing. Fix the issues above and re-run ./start.sh${NC}"
  exit 1
fi

echo -e "${GREEN}==> All prerequisites met. Starting TribeEco...${NC}"
echo ""

# ── Start services ────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

# 1. Build and start all databases + backend services via docker-compose
echo "[1/4] Building and starting Docker services..."
info "Building images (this may take a minute on first run)..."
docker-compose -f "$ROOT_DIR/docker-compose.yml" up -d --build 2>&1 | while read line; do
  echo "       $line"
done

# 2. Wait for databases to be healthy
echo "[2/4] Waiting for databases to be healthy..."
for i in $(seq 1 30); do
  ALL_HEALTHY=1
  for svc in er-db hub-db; do
    STATUS=$(docker-compose -f "$ROOT_DIR/docker-compose.yml" ps "$svc" --format json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('Health',''))" 2>/dev/null || echo "")
    if [ "$STATUS" != "healthy" ]; then
      ALL_HEALTHY=0
    fi
  done
  if [ "$ALL_HEALTHY" -eq 1 ]; then
    break
  fi
  printf "\r       Waiting for databases... (%ds)" "$i"
  sleep 1
done
echo ""
ok "Databases ready"

# 3. Wait for backend services to be healthy
echo "[3/4] Waiting for backend services..."
wait_for_service() {
  local name=$1
  local url=$2
  local max_wait=$3
  for i in $(seq 1 $max_wait); do
    if curl -sf "$url" > /dev/null 2>&1; then
      ok "$name is healthy"
      return 0
    fi
    sleep 1
  done
  warn "$name did not become healthy in ${max_wait}s (may still be starting)"
  return 0
}

wait_for_service "Hub" "http://localhost:4000/health" 30
wait_for_service "ER server" "http://localhost:3003/health" 30

# 4. Start the frontend app
echo "[4/4] Starting frontend app (Next.js on port 3002)..."
cd "$ROOT_DIR/tribe-twitter-app"
pnpm dev -p 3002 > "$LOG_DIR/tribe-twitter-app.log" 2>&1 &
echo $! > "$LOG_DIR/tribe-twitter-app.pid"

# Wait for frontend to be reachable
for i in $(seq 1 20); do
  if curl -sf "http://localhost:3002" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          TribeEco is running!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "    ${CYAN}Frontend app:${NC}   http://localhost:3002"
echo -e "    ${CYAN}Hub:${NC}            http://localhost:4000"
echo -e "    ${CYAN}ER server:${NC}      http://localhost:3003"
echo ""
echo -e "    ${CYAN}Network:${NC}        Solana Devnet"
echo -e "    ${CYAN}App logs:${NC}       $LOG_DIR/tribe-twitter-app.log"
echo -e "    ${CYAN}Docker logs:${NC}    docker-compose logs -f"
echo -e "    ${CYAN}Stop with:${NC}      ./stop.sh"
echo ""
echo -e "    ${YELLOW}Tip:${NC} Install Phantom wallet browser extension to connect."
echo ""
