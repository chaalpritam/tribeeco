#!/bin/bash
#
# Setup a TribeEco seed node on a fresh Ubuntu VPS
#
# Usage: ssh into your VPS and run:
#   curl -fsSL <raw-github-url>/deploy/seed/setup-seed.sh | bash
#
# Or clone the repo and run:
#   ./deploy/seed/setup-seed.sh
#
# Prerequisites:
#   - Ubuntu 22.04+ (Oracle Cloud free tier, DigitalOcean, etc.)
#   - Port 4000 open in cloud firewall / security list
#
# Oracle Cloud: Also open port 4000 in your VCN Security List:
#   Networking → Virtual Cloud Networks → Security Lists → Add Ingress Rule
#   Source: 0.0.0.0/0, Protocol: TCP, Dest Port: 4000

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco Seed Node Setup                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

SEED_DIR="$HOME/tribe-seed"

# 1. Install Docker
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "  Docker installed. You may need to log out and back in for group changes."
fi

# 2. Clone repo
if [ ! -d "$SEED_DIR" ]; then
  echo "==> Cloning TribeEco..."
  git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git "$SEED_DIR"
else
  echo "==> Updating TribeEco..."
  git -C "$SEED_DIR" pull
  git -C "$SEED_DIR" submodule update --init --recursive
fi

# 3. Start seed
echo "==> Building and starting seed node..."
cd "$SEED_DIR/deploy/seed"
docker compose -f docker-compose.seed.yml up -d --build

# 4. Open firewall (Ubuntu iptables)
if command -v iptables &>/dev/null; then
  sudo iptables -I INPUT -p tcp --dport 4000 -j ACCEPT 2>/dev/null || true
fi

# 5. Wait for health
echo "==> Waiting for hub to become healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:4000/health > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

# 6. Print connection info
PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Seed node is running!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Hub API:${NC}    http://$PUBLIC_IP:4000"
echo -e "  ${BOLD}Health:${NC}     http://$PUBLIC_IP:4000/health"
echo -e "  ${BOLD}Gossip:${NC}     ws://$PUBLIC_IP:4000/gossip"
echo ""
echo -e "  ${BOLD}On each tribe node, run:${NC}"
echo -e "    ${CYAN}tribe seed set ws://$PUBLIC_IP:4000/gossip${NC}"
echo ""
echo -e "  ${BOLD}Manage:${NC}"
echo -e "    Logs:     docker compose -f docker-compose.seed.yml logs -f hub"
echo -e "    Restart:  docker compose -f docker-compose.seed.yml restart"
echo -e "    Stop:     docker compose -f docker-compose.seed.yml down"
echo ""
