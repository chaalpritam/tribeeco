#!/bin/bash
#
# Provision a production TribeEco node (hub + ER server) on a fresh
# Ubuntu EC2 instance, fronted by Caddy for automatic Let's Encrypt TLS.
#
#   https://$DOMAIN        -> hub  (API + wss gossip)
#   wss://$DOMAIN/gossip   -> hub gossip endpoint
#   https://$DOMAIN:3003   -> ER server (instant follows + L1 settlement)
#
# Usage on the EC2 box:
#   DOMAIN=seed.example.com bash setup-aws.sh
#   bash setup-aws.sh                 # prompts for the domain
#
# Prerequisites:
#   - Ubuntu 22.04+ EC2 instance (t3.medium / 4 GB RAM recommended).
#   - An Elastic IP attached, with a DNS A record pointing $DOMAIN at it
#     (verify: dig +short $DOMAIN  ->  your Elastic IP).
#   - Security group inbound: TCP 22 (your IP), 80, 443, AND 3003 open
#     to 0.0.0.0/0.  80 = ACME challenge, 443 = hub, 3003 = ER server.
#
# Solana: this node runs on devnet. The ER server needs a funded devnet
# wallet to settle follows to L1; the script generates one and airdrops
# to it (best effort — devnet airdrops are rate-limited).

set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     TribeEco Production Node (AWS) Setup     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ -z "$DOMAIN" ]; then
  read -p "Domain pointing at this server (e.g. seed.example.com): " DOMAIN
fi
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}DOMAIN is required.${NC} Set a DNS A record, then re-run with:"
  echo "  DOMAIN=seed.example.com bash setup-aws.sh"
  exit 1
fi
export DOMAIN

PROD_DIR="$HOME/tribe-prod"
WALLET="$PROD_DIR/deploy/prod/server-wallet.json"

# 1. Docker
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "  Docker installed. Log out/in if the group change hasn't taken effect."
fi

# 2. Solana CLI (only needed to mint + fund the ER server wallet)
if ! command -v solana-keygen &>/dev/null; then
  echo "==> Installing Solana CLI..."
  sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
  export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
fi

# 3. Clone / update repo
if [ ! -d "$PROD_DIR" ]; then
  echo "==> Cloning TribeEco..."
  git clone --recurse-submodules https://github.com/chaalpritam/TribeEco.git "$PROD_DIR"
else
  echo "==> Updating TribeEco..."
  git -C "$PROD_DIR" pull
  git -C "$PROD_DIR" submodule update --init --recursive
fi

# 4. ER server wallet — generate once, then airdrop devnet SOL.
if [ ! -f "$WALLET" ]; then
  echo "==> Generating ER server wallet..."
  solana-keygen new --no-bip39-passphrase --silent --outfile "$WALLET"
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
  echo -e "  ${YELLOW}! Airdrop didn't land (devnet rate limits). Fund manually later:${NC}"
  echo "    solana airdrop 2 $PUBKEY --url https://api.devnet.solana.com"
  echo "    or paste $PUBKEY into https://faucet.solana.com"
fi

# 5. Build + start the stack
echo "==> Building and starting hub + ER + Caddy for $DOMAIN..."
cd "$PROD_DIR/deploy/prod"
docker compose -f docker-compose.prod.yml up -d --build

# 6. Firewall (host iptables). Cloud security group must ALSO open these.
if command -v iptables &>/dev/null; then
  for p in 80 443 3003; do
    sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
  done
fi

# 7. Wait for the hub healthcheck
echo "==> Waiting for hub to become healthy..."
for i in $(seq 1 60); do
  cid=$(docker compose -f docker-compose.prod.yml ps -q hub 2>/dev/null)
  if [ -n "$cid" ] && [ "$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null)" = "healthy" ]; then
    break
  fi
  sleep 2
done

# 8. End-to-end reachability over the public domain (informational)
PUBLIC_IP=$(curl -s ifconfig.me)
curl -sf --max-time 10 "https://$DOMAIN/health" >/dev/null 2>&1 && HUB_OK=1 || HUB_OK=0
curl -sf --max-time 10 "https://$DOMAIN:3003/health" >/dev/null 2>&1 && ER_OK=1 || ER_OK=0

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Production node is running!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Domain:${NC}      $DOMAIN"
echo -e "  ${BOLD}Public IP:${NC}   $PUBLIC_IP"
echo -e "  ${BOLD}Hub API:${NC}     https://$DOMAIN"
echo -e "  ${BOLD}Gossip:${NC}      wss://$DOMAIN/gossip"
echo -e "  ${BOLD}ER server:${NC}   https://$DOMAIN:3003"
echo ""
[ "$HUB_OK" -eq 1 ] && echo -e "  ${GREEN}✔ https://$DOMAIN/health responded.${NC}" \
                     || echo -e "  ${YELLOW}! https://$DOMAIN/health not reachable yet (DNS / cert / SG port 443).${NC}"
[ "$ER_OK" -eq 1 ]  && echo -e "  ${GREEN}✔ https://$DOMAIN:3003/health responded.${NC}" \
                     || echo -e "  ${YELLOW}! https://$DOMAIN:3003/health not reachable yet (SG must open TCP 3003).${NC}"
echo ""
echo -e "  ${BOLD}Point a tribe install at this node:${NC}"
echo -e "    ${CYAN}tribe seed set wss://$DOMAIN/gossip${NC}"
echo -e "  ${BOLD}Point the demo app at it:${NC}"
echo -e "    ${CYAN}tribe-app link https://$DOMAIN${NC}   ${YELLOW}# ER URL becomes https://$DOMAIN:3003${NC}"
echo ""
echo -e "  ${BOLD}Manage:${NC}"
echo -e "    Logs:    docker compose -f docker-compose.prod.yml logs -f hub er-server"
echo -e "    Caddy:   docker compose -f docker-compose.prod.yml logs -f caddy"
echo -e "    Restart: DOMAIN=$DOMAIN docker compose -f docker-compose.prod.yml restart"
echo -e "    Stop:    docker compose -f docker-compose.prod.yml down"
echo ""
