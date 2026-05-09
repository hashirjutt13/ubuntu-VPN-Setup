# Ubuntu WireGuard + wstunnel VPN Setup

One-command WireGuard VPN setup script for an Ubuntu server. The script installs WireGuard, enables IP forwarding, creates server and client keys, starts WireGuard on UDP `51820`, and starts `wstunnel` on TCP `443` so WireGuard traffic can be wrapped inside a WebSocket/TLS-looking connection when the client side also runs `wstunnel`.

## Requirements

- Ubuntu server with `sudo` access
- Internet access from the server
- TCP port `443` open in your cloud firewall/security group
- Optional direct fallback: UDP port `51820` open in your cloud firewall/security group
- WireGuard app installed on your phone or client device
- A client-side way to run `wstunnel` if you want TCP `443` tunneling

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

1. Make sure TCP port `443` is open in your server firewall and cloud security group.
2. Run the generated wstunnel client command on the client side.
3. Import the generated WireGuard config into your WireGuard client.
4. Connect to the VPN and visit `https://whatismyip.com` to verify that your traffic is using the server IP.

The generated configs are saved on the server at:

```text
/root/client.conf
/root/client-wstunnel.conf
/root/client-direct.conf
/root/wstunnel-client-command.txt
```

## Important iPhone Note

The official iPhone WireGuard app cannot run `wstunnel` by itself. For the TCP `443` tunnel mode to work, something on the client side must run the `wstunnel client` command and listen locally on UDP `51820`.

That means one of these must be true:

- You use a compatible iOS tunneling app that can run `wstunnel` or an equivalent WebSocket UDP tunnel.
- You run `wstunnel client` on a travel router, laptop, or another device, and route the iPhone through that device.
- You use the direct fallback config, which uses normal WireGuard UDP `51820` and may still be blocked on some mobile networks.

For wstunnel mode, the WireGuard endpoint is:

```text
127.0.0.1:51820
```

That is intentional. WireGuard sends traffic to the local wstunnel client, and wstunnel carries it to the server over TCP `443`.

## Notes

- The script is intended for a fresh Ubuntu server.
- Re-running it will regenerate WireGuard keys and overwrite `/etc/wireguard/wg0.conf` and `/root/client.conf`.
- Keep `/root/client.conf` private because it contains the client private key.
- wstunnel uses its embedded self-signed TLS certificate by default. For a cleaner production setup, use a domain and a valid TLS certificate.
