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
apt-get install -y wireguard wireguard-tools qrencode iptables-persistent > /dev/null 2>&1
log "Dependencies installed"

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
ListenPort = 51820
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

[Peer]
PublicKey = ${SERVER_PUBLIC}
Endpoint = ${PUBLIC_IP}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /root/client.conf
log "Client config written"

# ---- Start WireGuard ----
info "Starting WireGuard..."
systemctl enable wg-quick@wg0 > /dev/null 2>&1
systemctl restart wg-quick@wg0
log "WireGuard started"

# ---- Save iptables rules ----
info "Saving firewall rules..."
netfilter-persistent save > /dev/null 2>&1
log "Firewall rules saved"

# ---- Verify ----
info "Verifying setup..."
sleep 1
WG_STATUS=$(wg show wg0 2>&1)
if echo "$WG_STATUS" | grep -q "listening port: 51820"; then
  log "WireGuard is running on port 51820"
else
  error "WireGuard failed to start. Run: sudo wg show"
fi

# ---- Print QR Code ----
echo ""
echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}         Scan this QR code on your iPhone       ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""
qrencode -t ansiutf8 < /root/client.conf
echo ""
echo -e "${BOLD}================================================${NC}"
echo -e "${GREEN}${BOLD} VPN Setup Complete!${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""
echo -e "  ${CYAN}Server IP   :${NC} $PUBLIC_IP"
echo -e "  ${CYAN}VPN Port    :${NC} 51820 (UDP)"
echo -e "  ${CYAN}Client IP   :${NC} 10.0.0.2"
echo -e "  ${CYAN}Client conf :${NC} /root/client.conf"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  1. Make sure UDP port 51820 is open in AWS Security Group"
echo -e "  2. Open WireGuard app on iPhone"
echo -e "  3. Tap + → Create from QR code → Scan above"
echo -e "  4. Connect and visit whatismyip.com to verify"
echo ""
