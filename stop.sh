#!/bin/bash

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT_DIR/.logs"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}==> Stopping TribeEco...${NC}"

# 1. Stop the frontend app
if [ -f "$LOG_DIR/tribe-twitter-app.pid" ]; then
  PID=$(cat "$LOG_DIR/tribe-twitter-app.pid")
  if kill -0 "$PID" 2>/dev/null; then
    echo "  [1/2] Stopping frontend app (PID $PID)..."
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  else
    echo "  [1/2] Frontend app already stopped."
  fi
  rm -f "$LOG_DIR/tribe-twitter-app.pid"
else
  echo "  [1/2] No frontend app PID found."
fi

# 2. Stop Docker services
echo "  [2/2] Stopping Docker services..."
docker-compose -f "$ROOT_DIR/docker-compose.yml" down

echo ""
echo -e "${GREEN}==> TribeEco stopped.${NC}"
echo ""
