#!/bin/bash

# Script to toggle between VPN and direct IP for ARR stack
# Usage: ./toggle-vpn.sh [on|off|status]

COMPOSE_FILE="docker-compose.arr-stack.yml"
OVERRIDE_FILE="docker-compose.no-vpn.yml"
COMPOSE_DIR=$(pwd)

cd "$COMPOSE_DIR" || exit 1

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if VPN is active
check_vpn_status() {
    if docker ps --format '{{.Names}}' | grep -q "^gluetun$"; then
        echo -e "${GREEN}VPN Mode: ACTIVE${NC}"
        echo "Gluetun is running. Download clients are using VPN."
        docker exec gluetun wget -qO- --timeout=3 https://api.ipify.org 2>/dev/null && echo " (VPN Exit IP)"
    else
        echo -e "${YELLOW}Direct Mode: ACTIVE${NC}"
        echo "Gluetun is stopped. Download clients are using direct IP."
        curl -s --max-time 3 https://api.ipify.org 2>/dev/null && echo " (Your Real IP)"
    fi
}

# Function to enable VPN mode
enable_vpn() {
    echo -e "${GREEN}Enabling VPN mode...${NC}"

    # Remove override file if it exists
    if [ -f "$OVERRIDE_FILE" ]; then
        rm "$OVERRIDE_FILE"
        echo "Removed no-VPN override file"
    fi

    # Start the stack normally (with Gluetun)
    docker compose -f "$COMPOSE_FILE" up -d

    echo -e "${GREEN}VPN mode enabled!${NC}"
    echo "Waiting for Gluetun to connect..."
    sleep 5
    check_vpn_status
}

# Function to disable VPN mode
disable_vpn() {
    echo -e "${YELLOW}Disabling VPN mode...${NC}"

    # Create override file to bypass Gluetun
    cat > "$OVERRIDE_FILE" << 'EOF'
services:
  # Stop Gluetun
  gluetun:
    restart: "no"
    command: ["sh", "-c", "exit 0"]

  # Run download clients on bridge network instead of through Gluetun
  qbittorrent:
    network_mode: bridge
    ports:
      - "8085:8085"
    depends_on:
      gluetun:
        condition: service_started
        required: false

  sonarr:
    network_mode: bridge
    ports:
      - "8989:8989"
    depends_on:
      gluetun:
        condition: service_started
        required: false

  prowlarr:
    network_mode: bridge
    ports:
      - "9696:9696"
    depends_on:
      gluetun:
        condition: service_started
        required: false

  radarr:
    network_mode: bridge
    ports:
      - "7878:7878"
    depends_on:
      gluetun:
        condition: service_started
        required: false
EOF

    # Stop Gluetun and restart download clients with override
    docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" up -d

    echo -e "${YELLOW}Direct mode enabled!${NC}"
    echo "Download clients are now using your real IP"
    sleep 2
    check_vpn_status
}

# Main script logic
case "${1:-status}" in
    on|enable|vpn)
        enable_vpn
        ;;
    off|disable|direct)
        disable_vpn
        ;;
    status|check)
        check_vpn_status
        ;;
    *)
        echo "Usage: $0 {on|off|status}"
        echo ""
        echo "  on/enable/vpn    - Enable VPN mode (route through Gluetun)"
        echo "  off/disable/direct - Disable VPN mode (use direct IP)"
        echo "  status/check     - Check current mode"
        exit 1
        ;;
esac
