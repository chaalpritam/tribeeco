#!/bin/bash
#
# Setup a TribeEco seed node on a fresh Ubuntu VPS, fronted by Caddy
# for automatic Let's Encrypt TLS. The seed listens on wss://$DOMAIN.
#
# Usage: ssh into your VPS and run with a domain pointing at it:
#   DOMAIN=seed.tribeapp.wtf bash setup-seed.sh
#
# Or interactively (the script prompts for a domain):
#   bash setup-seed.sh
#
# Prerequisites:
#   - Ubuntu 22.04+ (Oracle Cloud free tier, DigitalOcean, etc.)
#   - A DNS A record pointing $DOMAIN at this server's public IP
#   - Ports 80 and 443 open in cloud firewall / security list
#
# Oracle Cloud: Open ports 80 + 443 in your VCN Security List:
#   Networking → Virtual Cloud Networks → Security Lists → Add Ingress Rules
#   Source: 0.0.0.0/0, Protocol: TCP, Dest Ports: 80 and 443
#   (Port 4000 is NOT exposed publicly — Caddy fronts the hub.)

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco Seed Node Setup                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Domain is mandatory — Caddy uses it to provision a Let's Encrypt
# cert at boot. DNS must already resolve to this box's public IP or
# the ACME HTTP-01 challenge fails and the cert never issues.
if [ -z "$DOMAIN" ]; then
  read -p "Domain pointing at this server (e.g. seed.tribeapp.wtf): " DOMAIN
fi
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}DOMAIN is required.${NC}"
  echo "Set a DNS A record first, then re-run with:"
  echo "  DOMAIN=seed.example.com bash setup-seed.sh"
  exit 1
fi
export DOMAIN

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

# 3. Start seed (DOMAIN is exported, picked up by Caddy via Caddyfile)
echo "==> Building and starting seed node for $DOMAIN..."
cd "$SEED_DIR/deploy/seed"
docker compose -f docker-compose.seed.yml up -d --build

# 4. Open firewall (Ubuntu iptables) — 80 for ACME HTTP-01 challenge,
#    443 for the actual wss:// traffic. Port 4000 stays internal.
if command -v iptables &>/dev/null; then
  sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
  sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
fi

# 5. Wait for hub container's healthcheck to go green. Caddy's TLS
#    issuance happens in parallel and can take 10-60s on first boot.
echo "==> Waiting for hub to become healthy..."
for i in $(seq 1 60); do
  cid=$(docker compose -f docker-compose.seed.yml ps -q hub 2>/dev/null)
  if [ -n "$cid" ] && [ "$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null)" = "healthy" ]; then
    break
  fi
  sleep 2
done

# 6. Best-effort end-to-end check via the public domain. Will fail
#    if DNS hasn't propagated yet or Caddy is still negotiating the
#    cert — that's not fatal, just informational.
echo "==> Verifying public reachability at https://$DOMAIN/health..."
PUBLIC_IP=$(curl -s ifconfig.me)
if curl -sf --max-time 10 "https://$DOMAIN/health" > /dev/null 2>&1; then
  PUBLIC_OK=1
else
  PUBLIC_OK=0
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Seed node is running!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Domain:${NC}     $DOMAIN"
echo -e "  ${BOLD}Public IP:${NC}  $PUBLIC_IP"
echo -e "  ${BOLD}Hub API:${NC}    https://$DOMAIN"
echo -e "  ${BOLD}Health:${NC}     https://$DOMAIN/health"
echo -e "  ${BOLD}Gossip:${NC}     wss://$DOMAIN/gossip"
echo ""

if [ "$PUBLIC_OK" -eq 1 ]; then
  echo -e "  ${GREEN}✔ https://$DOMAIN/health responded — seed is live.${NC}"
else
  echo -e "  ${YELLOW}! https://$DOMAIN/health did not respond yet.${NC}"
  echo "    Common causes:"
  echo "      • DNS A record for $DOMAIN doesn't point at $PUBLIC_IP yet"
  echo "      • Cloud firewall (Oracle VCN / AWS SG / etc.) still blocking 80/443"
  echo "      • Caddy still negotiating the cert (give it ~60s and retry)"
  echo "    Tail Caddy: docker compose -f docker-compose.seed.yml logs -f caddy"
fi
echo ""
echo -e "  ${BOLD}On each tribe node, run:${NC}"
echo -e "    ${CYAN}tribe seed set wss://$DOMAIN/gossip${NC}"
echo ""
echo -e "  ${BOLD}Manage:${NC}"
echo -e "    Logs:     docker compose -f docker-compose.seed.yml logs -f hub"
echo -e "    Caddy:    docker compose -f docker-compose.seed.yml logs -f caddy"
echo -e "    Restart:  DOMAIN=$DOMAIN docker compose -f docker-compose.seed.yml restart"
echo -e "    Stop:     docker compose -f docker-compose.seed.yml down"
echo ""
