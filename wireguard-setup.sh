#!/bin/bash

# ============================================================
#   WireGuard VPN - One Command Setup Script
#   Run as: sudo bash wireguard-setup.sh
# ============================================================

set -e

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WG_PORT=51820
WSTUNNEL_PORT=443
WSTUNNEL_PATH=${WSTUNNEL_PATH:-}

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
info()   { echo -e "${CYAN}[→]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }

echo ""
echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}       WireGuard VPN - Auto Setup Script        ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""

# ---- Must run as root ----
[ "$EUID" -ne 0 ] && error "Please run as root: sudo bash wireguard-setup.sh"

# ---- Detect public IP ----
info "Detecting server public IP..."
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
[ -z "$PUBLIC_IP" ] && error "Could not detect public IP. Check internet connection."
log "Public IP: $PUBLIC_IP"

# ---- Detect network interface ----
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
[ -z "$INTERFACE" ] && error "Could not detect network interface."
log "Network interface: $INTERFACE"

# ---- Install dependencies ----
info "Installing WireGuard and dependencies..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools qrencode iptables-persistent curl ca-certificates tar openssl > /dev/null 2>&1
log "Dependencies installed"

[ -z "$WSTUNNEL_PATH" ] && WSTUNNEL_PATH=$(openssl rand -hex 24)

# ---- Install wstunnel ----
info "Installing wstunnel..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) WSTUNNEL_ARCH="amd64" ;;
  aarch64|arm64) WSTUNNEL_ARCH="arm64" ;;
  *) error "Unsupported CPU architecture for wstunnel: $ARCH" ;;
esac

WSTUNNEL_VERSION=$(curl -fsSL https://api.github.com/repos/erebe/wstunnel/releases/latest \
  | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' \
  | head -n1)
[ -z "$WSTUNNEL_VERSION" ] && error "Could not detect latest wstunnel version."

TMP_DIR=$(mktemp -d)
WSTUNNEL_URL="https://github.com/erebe/wstunnel/releases/download/v${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_${WSTUNNEL_ARCH}.tar.gz"
curl -fsSL "$WSTUNNEL_URL" -o "$TMP_DIR/wstunnel.tar.gz"
tar -xzf "$TMP_DIR/wstunnel.tar.gz" -C "$TMP_DIR"
install -m 755 "$TMP_DIR/wstunnel" /usr/local/bin/wstunnel
rm -rf "$TMP_DIR"
log "wstunnel installed: $(/usr/local/bin/wstunnel --version 2>/dev/null | head -n1)"

# ---- Enable IP forwarding ----
info "Enabling IP forwarding..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null
log "IP forwarding enabled"

# ---- Generate server keys ----
info "Generating server keypair..."
SERVER_PRIVATE=$(wg genkey)
SERVER_PUBLIC=$(echo "$SERVER_PRIVATE" | wg pubkey)
log "Server keys generated"

# ---- Generate client keys ----
info "Generating client keypair..."
CLIENT_PRIVATE=$(wg genkey)
CLIENT_PUBLIC=$(echo "$CLIENT_PRIVATE" | wg pubkey)
log "Client keys generated"

# ---- Write server config ----
info "Writing server config..."
mkdir -p /etc/wireguard
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE}

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = 10.0.0.2/32
EOF
chmod 600 /etc/wireguard/wg0.conf
log "Server config written"

# ---- Write client config ----
info "Writing client config..."
cat > /root/client.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = 10.0.0.2/24
DNS = 1.1.1.1
MTU = 1300

[Peer]
PublicKey = ${SERVER_PUBLIC}
Endpoint = 127.0.0.1:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /root/client.conf

cp /root/client.conf /root/client-wstunnel.conf
cat > /root/client-direct.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC}
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /root/client-wstunnel.conf /root/client-direct.conf
log "Client configs written"

# ---- Write wstunnel client command ----
info "Writing wstunnel client helper command..."
cat > /root/wstunnel-client-command.txt << EOF
wstunnel client --http-upgrade-path-prefix ${WSTUNNEL_PATH} -L 'udp://127.0.0.1:${WG_PORT}:127.0.0.1:${WG_PORT}?timeout_sec=0' wss://${PUBLIC_IP}:${WSTUNNEL_PORT}
EOF
chmod 600 /root/wstunnel-client-command.txt
log "wstunnel client command written"

# ---- Start WireGuard ----
info "Starting WireGuard..."
systemctl enable wg-quick@wg0 > /dev/null 2>&1
systemctl restart wg-quick@wg0
log "WireGuard started"

# ---- Start wstunnel ----
info "Starting wstunnel on TCP ${WSTUNNEL_PORT}..."
cat > /etc/systemd/system/wstunnel-wireguard.service << EOF
[Unit]
Description=wstunnel for WireGuard over TCP ${WSTUNNEL_PORT}
After=network-online.target wg-quick@wg0.service
Wants=network-online.target
Requires=wg-quick@wg0.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel server --restrict-to 127.0.0.1:${WG_PORT} --restrict-http-upgrade-path-prefix ${WSTUNNEL_PATH} wss://[::]:${WSTUNNEL_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
chmod 600 /etc/systemd/system/wstunnel-wireguard.service
systemctl daemon-reload
systemctl enable wstunnel-wireguard > /dev/null 2>&1
systemctl restart wstunnel-wireguard
log "wstunnel started"

# ---- Save iptables rules ----
info "Saving firewall rules..."
netfilter-persistent save > /dev/null 2>&1
log "Firewall rules saved"

# ---- Verify ----
info "Verifying setup..."
sleep 1
WG_STATUS=$(wg show wg0 2>&1)
if echo "$WG_STATUS" | grep -q "listening port: ${WG_PORT}"; then
  log "WireGuard is running on UDP ${WG_PORT}"
else
  error "WireGuard failed to start. Run: sudo wg show"
fi

if systemctl is-active --quiet wstunnel-wireguard; then
  log "wstunnel is running on TCP ${WSTUNNEL_PORT}"
else
  error "wstunnel failed to start. Run: sudo journalctl -u wstunnel-wireguard"
fi

# ---- Print QR Code ----
echo ""
echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}     WireGuard client config for wstunnel mode  ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""
qrencode -t ansiutf8 < /root/client.conf
echo ""
echo -e "${BOLD}================================================${NC}"
echo -e "${GREEN}${BOLD} VPN Setup Complete!${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""
echo -e "  ${CYAN}Server IP   :${NC} $PUBLIC_IP"
echo -e "  ${CYAN}WireGuard   :${NC} ${WG_PORT} (UDP)"
echo -e "  ${CYAN}wstunnel    :${NC} ${WSTUNNEL_PORT} (TCP)"
echo -e "  ${CYAN}Client IP   :${NC} 10.0.0.2"
echo -e "  ${CYAN}WG tunnel   :${NC} /root/client-wstunnel.conf"
echo -e "  ${CYAN}WG direct   :${NC} /root/client-direct.conf"
echo -e "  ${CYAN}wstunnel cmd:${NC} /root/wstunnel-client-command.txt"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  1. Open TCP port ${WSTUNNEL_PORT} in your cloud firewall/security group"
echo -e "  2. For direct fallback, optionally open UDP port ${WG_PORT}"
echo -e "  3. Run the wstunnel client command on the client side"
echo -e "  4. Import /root/client-wstunnel.conf into WireGuard"
echo -e "  5. Connect and visit whatismyip.com to verify"
echo ""
warn "The official iPhone WireGuard app cannot run wstunnel by itself."
warn "It needs a separate client-side wstunnel path, such as a router, laptop, or compatible iOS tunneling app."
echo ""
