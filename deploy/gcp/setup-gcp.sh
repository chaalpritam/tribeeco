#!/bin/bash
#
# Provision a TribeEco protocol node (hub + ER server) on a fresh
# Ubuntu Google Compute Engine VM, fronted by Caddy for TLS.

set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco Protocol Node (GCP) Setup       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ -z "$DOMAIN" ]; then
  read -p "Domain pointing at this server (e.g. seed.example.com): " DOMAIN
fi
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}DOMAIN is required.${NC} Set a DNS A record, then re-run with:"
  echo "  DOMAIN=seed.example.com bash setup-gcp.sh"
  exit 1
fi
export DOMAIN

INSTALL_DIR="${INSTALL_DIR:-/opt/tribe-gcp}"
WALLET="$INSTALL_DIR/deploy/gcp/server-wallet.json"

if ! command -v git >/dev/null 2>&1; then
  echo "==> Installing git..."
  sudo apt-get update
  sudo apt-get install -y git ca-certificates curl
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v solana-keygen >/dev/null 2>&1; then
  echo "==> Installing Solana CLI..."
  sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
  export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
fi

if [ ! -d "$INSTALL_DIR" ]; then
  echo "==> Cloning TribeEco..."
  sudo git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git "$INSTALL_DIR"
else
  echo "==> Updating TribeEco..."
  sudo git -C "$INSTALL_DIR" pull
  sudo git -C "$INSTALL_DIR" submodule update --init --recursive
fi

sudo mkdir -p "$(dirname "$WALLET")"
if [ ! -f "$WALLET" ]; then
  echo "==> Generating ER server wallet..."
  solana-keygen new --no-bip39-passphrase --silent --outfile /tmp/tribe-gcp-server-wallet.json
  sudo mv /tmp/tribe-gcp-server-wallet.json "$WALLET"
  sudo chmod 600 "$WALLET"
fi

PUBKEY=$(solana-keygen pubkey "$WALLET")
echo "  ER server wallet: $PUBKEY"

echo "==> Funding wallet on devnet (best effort)..."
solana config set --url https://api.devnet.solana.com >/dev/null 2>&1 || true
for i in 1 2 3; do
  if solana airdrop 2 "$PUBKEY" --url https://api.devnet.solana.com >/dev/null 2>&1; then
    break
  fi
  sleep 3
done
BAL=$(solana balance "$PUBKEY" --url https://api.devnet.solana.com 2>/dev/null || echo "unknown")
echo "  Balance: $BAL"
if [ "$BAL" = "0 SOL" ] || [ "$BAL" = "unknown" ]; then
  echo -e "  ${YELLOW}! Airdrop did not land. Fund manually later:${NC}"
  echo "    solana airdrop 2 $PUBKEY --url https://api.devnet.solana.com"
fi

echo "==> Building and starting hub + ER + Caddy for $DOMAIN..."
cd "$INSTALL_DIR/deploy/gcp"
sudo --preserve-env=DOMAIN,HUB_ID,POSTGRES_PASSWORD,SOLANA_RPC_URL,SOLANA_WS_URL,PEERS \
  docker compose -f docker-compose.gcp.yml up -d --build

if command -v iptables >/dev/null 2>&1; then
  for p in 80 443 3003; do
    sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
  done
fi

echo "==> Waiting for hub to become healthy..."
for i in $(seq 1 60); do
  cid=$(sudo docker compose -f docker-compose.gcp.yml ps -q hub 2>/dev/null)
  if [ -n "$cid" ] && [ "$(sudo docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null)" = "healthy" ]; then
    break
  fi
  sleep 2
done

PUBLIC_IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" \
  2>/dev/null || curl -s ifconfig.me)
curl -sf --max-time 10 "https://$DOMAIN/health" >/dev/null 2>&1 && HUB_OK=1 || HUB_OK=0
curl -sf --max-time 10 "https://$DOMAIN:3003/health" >/dev/null 2>&1 && ER_OK=1 || ER_OK=0

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Google Cloud protocol node is running!   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Domain:${NC}      $DOMAIN"
echo -e "  ${BOLD}Public IP:${NC}   $PUBLIC_IP"
echo -e "  ${BOLD}Hub API:${NC}     https://$DOMAIN"
echo -e "  ${BOLD}Gossip:${NC}      wss://$DOMAIN/gossip"
echo -e "  ${BOLD}ER server:${NC}   https://$DOMAIN:3003"
echo ""
[ "$HUB_OK" -eq 1 ] && echo -e "  ${GREEN}✔ https://$DOMAIN/health responded.${NC}" \
                     || echo -e "  ${YELLOW}! https://$DOMAIN/health not reachable yet (DNS / cert / firewall 443).${NC}"
[ "$ER_OK" -eq 1 ]  && echo -e "  ${GREEN}✔ https://$DOMAIN:3003/health responded.${NC}" \
                     || echo -e "  ${YELLOW}! https://$DOMAIN:3003/health not reachable yet (firewall must open TCP 3003).${NC}"
echo ""
echo -e "  ${BOLD}Point each Mac mini hub at this node:${NC}"
echo -e "    ${CYAN}tribe seed set wss://$DOMAIN/gossip${NC}"
echo ""

