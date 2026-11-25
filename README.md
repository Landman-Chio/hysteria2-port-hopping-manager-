# Hysteria 2 Port-Hopping Manager

**Version:** v1.4.2  
**Platform:** Ubuntu 22.04 / 24.04 (Debian-based systems may work)

A Bash-based interactive manager for deploying and maintaining a standalone Hysteria 2 port-hopping server. It is designed to coexist with S-UI/Xray and does not intentionally modify their configuration.

## Features

- Install or reconfigure a Hysteria 2 server.
- Configure UDP port hopping (default range: `20000-50000`).
- Use an existing TLS certificate or request one with Let's Encrypt HTTP-01.
- Optional Salamander obfuscation.
- Configure masquerade responses.
- Select direct, SOCKS5/SOCKS5H, or HTTP/HTTPS outbound proxy.
- Generate client configuration, share links, and QR codes for v2rayNG, v2rayN, and Shadowrocket.
- View service status and logs, restart the service, update the Hysteria binary, and back up configuration.
- Change outbound proxy settings without rebuilding the node.
- Uninstall the service while retaining configuration, or perform a confirmed full cleanup.

## Install

Run as root on a supported Ubuntu server:

```bash
bash hysteria2_port_hopping_manager_v1.4.2.sh
```

The script installs required packages and the Hysteria binary when you select the install/configure menu item.

## Important notes

- Open the selected UDP port range in your cloud firewall/security group. If using Let's Encrypt HTTP-01, also allow inbound TCP port 80.
- SOCKS5 UDP support depends on the upstream proxy provider. HTTP/HTTPS proxy mode is TCP-only and does not support UDP forwarding.
- Generated share links and QR codes contain authentication credentials. Keep them private.
- Verify client-side port-hopping interval support and settings for the client application you use.
- The script requires root privileges for installation and service management.

## Menu

Run the script and follow the interactive menu. The menu includes installation/configuration, core updates, status/log viewing, restart, backup, client artifact regeneration, link display, outbound proxy changes, uninstall, and full cleanup.

## Validation

The v1.4.2 script passed a local `bash -n` syntax check before publication. This is not a substitute for a full deployment test on your own VPS, network, certificate, and upstream proxy.

## License

No license file is included yet. All rights are reserved by default unless the author adds a license.
