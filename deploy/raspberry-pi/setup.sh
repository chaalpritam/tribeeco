#!/bin/bash
#
# Setup a TribeEco node on Raspberry Pi
#
# Requirements:
#   - Raspberry Pi 4 (4GB+) or Raspberry Pi 5
#   - Raspberry Pi OS 64-bit (Bookworm or newer)
#   - Internet connection
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/raspberry-pi/setup.sh | bash
#
# Or clone and run:
#   ./deploy/raspberry-pi/setup.sh

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

TRIBE_DIR="$HOME/tribe"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco — Raspberry Pi Setup            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  fail "Unsupported architecture: $ARCH (need 64-bit ARM)"
  exit 1
fi
ok "Architecture: $ARCH"

# Check RAM
TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
if [ "$TOTAL_RAM_MB" -lt 3500 ]; then
  warn "Only ${TOTAL_RAM_MB}MB RAM detected. Minimum recommended: 4GB"
else
  ok "RAM: ${TOTAL_RAM_MB}MB"
fi

# 1. Install Docker
echo ""
echo "==> [1/5] Installing Docker..."
if command -v docker &>/dev/null; then
  ok "Docker already installed ($(docker --version | head -1))"
else
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  ok "Docker installed"
  warn "You may need to log out and back in for Docker group to take effect"
fi

# 2. Install Docker Compose plugin
echo "==> [2/5] Checking Docker Compose..."
if docker compose version &>/dev/null 2>&1; then
  ok "Docker Compose available"
else
  sudo apt-get update -qq && sudo apt-get install -y -qq docker-compose-plugin
  ok "Docker Compose installed"
fi

# 3. Install Node.js (for frontend)
echo "==> [3/5] Installing Node.js..."
if command -v node &>/dev/null; then
  ok "Node.js already installed ($(node --version))"
else
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
  ok "Node.js $(node --version) installed"
fi

# Install pnpm
if command -v pnpm &>/dev/null; then
  ok "pnpm already installed"
else
  npm install -g pnpm
  ok "pnpm installed"
fi

# 4. Clone TribeEco
echo "==> [4/5] Setting up TribeEco..."
if [ -d "$TRIBE_DIR" ]; then
  info "Updating existing installation..."
  git -C "$TRIBE_DIR" pull
  git -C "$TRIBE_DIR" submodule update --init --recursive
else
  git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git "$TRIBE_DIR"
fi
ok "TribeEco ready at $TRIBE_DIR"

# 5. Generate server wallet
echo "==> [5/5] Setting up server wallet..."
WALLET="$TRIBE_DIR/tribe-er-server/server-wallet.json"
PERSISTENT_WALLET="$HOME/.tribe/server-wallet.json"

if [ -f "$WALLET" ]; then
  ok "Server wallet already exists"
elif [ -f "$PERSISTENT_WALLET" ]; then
  cp "$PERSISTENT_WALLET" "$WALLET"
  ok "Server wallet restored from ~/.tribe/"
else
  # Install solana-keygen if needed
  if ! command -v solana-keygen &>/dev/null; then
    info "Installing Solana CLI..."
    sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)" 2>/dev/null
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
  fi
  mkdir -p "$HOME/.tribe"
  solana-keygen new -o "$WALLET" --no-bip39-passphrase 2>/dev/null
  cp "$WALLET" "$PERSISTENT_WALLET"
  ok "Server wallet generated (backed up to ~/.tribe/)"
fi

# Start services
echo ""
echo "==> Starting TribeEco..."
cd "$TRIBE_DIR"
docker compose up -d --build

# Wait for hub health
info "Waiting for hub to become healthy..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:4000/health > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Install frontend dependencies
info "Installing frontend dependencies..."
cd "$TRIBE_DIR/tribe-app"
pnpm install --silent 2>/dev/null

# Get network info
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     TribeEco is running on Raspberry Pi!     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Services:${NC}"
echo -e "    ${CYAN}Hub API:${NC}        http://localhost:4000"
echo -e "    ${CYAN}ER server:${NC}      http://localhost:3003"
if [ -n "$LOCAL_IP" ]; then
  echo ""
  echo -e "  ${BOLD}LAN access:${NC}"
  echo -e "    ${CYAN}Hub API:${NC}        http://${LOCAL_IP}:4000"
  echo -e "    ${CYAN}ER server:${NC}      http://${LOCAL_IP}:3003"
fi
echo ""
echo -e "  ${BOLD}Connect to seed node:${NC}"
echo -e "    curl -X POST http://localhost:4000/v1/peers \\"
echo -e "      -H 'Content-Type: application/json' \\"
echo -e "      -d '{\"url\": \"ws://<SEED_IP>:4000/gossip\"}'"
echo ""
echo -e "  ${BOLD}Start frontend (optional):${NC}"
echo -e "    cd $TRIBE_DIR/tribe-app && pnpm dev -p 3002"
echo ""
echo -e "  ${BOLD}Manage:${NC}"
echo -e "    Logs:      cd $TRIBE_DIR && docker compose logs -f"
echo -e "    Status:    docker compose ps"
echo -e "    Stop:      docker compose down"
echo -e "    Restart:   docker compose up -d"
echo ""
echo -e "  ${BOLD}Auto-start on boot:${NC}"
echo -e "    sudo systemctl enable docker"
echo -e "    Add to crontab: ${CYAN}@reboot cd $TRIBE_DIR && docker compose up -d${NC}"
echo ""
