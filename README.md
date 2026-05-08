# Ubuntu WireGuard VPN Setup

One-command WireGuard VPN setup script for an Ubuntu server. The script installs WireGuard, enables IP forwarding, creates server and client keys, starts the VPN service, saves firewall rules, and prints a QR code for importing the client config into the WireGuard mobile app.

## Requirements

- Ubuntu server with `sudo` access
- Internet access from the server
- UDP port `8443` open in your cloud firewall/security group
- WireGuard app installed on your phone or client device

## Quick Install

Run this on your Ubuntu server:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/hashirjutt13/ubuntu-VPN-Setup/main/wireguard-setup.sh)
```

## GitHub Setup

If you want to host the script in your own GitHub repository:

1. Create a new repo on GitHub, for example `vpn-setup`.
2. Upload `wireguard-setup.sh` into the repo.
3. Open the file on GitHub and click **Raw**.
4. Copy the raw URL. It should look like this:

```text
https://raw.githubusercontent.com/YOUR_USERNAME/vpn-setup/main/wireguard-setup.sh
```

5. Use the raw URL in the install command:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vpn-setup/main/wireguard-setup.sh)
```

## After Running

1. Make sure UDP port `8443` is open in your server firewall and cloud security group.
2. Open the WireGuard app on your phone.
3. Tap `+`, choose `Create from QR code`, and scan the QR code printed by the script.
4. Connect to the VPN and visit `https://whatismyip.com` to verify that your traffic is using the server IP.

The generated client config is saved on the server at:

```text
/root/client.conf
```

## Notes

- The script is intended for a fresh Ubuntu server.
- Re-running it will regenerate WireGuard keys and overwrite `/etc/wireguard/wg0.conf` and `/root/client.conf`.
- Keep `/root/client.conf` private because it contains the client private key.
