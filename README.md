# Hysteria 2 Port-Hopping Manager

**Version:** v1.4.3  
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

## Quick start

The repository is public. On a new Ubuntu VPS, run the following as root:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Landman-Chio/hysteria2-port-hopping-manager-/main/hysteria2_port_hopping_manager.sh")
```

The process-substitution launcher is supported. On first launch, the script installs a persistent copy at `/usr/local/sbin/hy2-manager` and creates `/usr/local/bin/hy2`. If you prefer a conventional local file:

```bash
curl -fL "https://raw.githubusercontent.com/Landman-Chio/hysteria2-port-hopping-manager-/main/hysteria2_port_hopping_manager.sh" -o /root/hysteria2_port_hopping_manager.sh
chmod +x /root/hysteria2_port_hopping_manager.sh
bash /root/hysteria2_port_hopping_manager.sh
```

After installation, run `hy2` to open the manager. Menu item **12** checks GitHub for the latest manager version, validates the downloaded script with `bash -n`, backs up the current manager, and updates it. A manager update does not rebuild the Hysteria service configuration or node.

Versioned release file: [hysteria2_port_hopping_manager_v1.4.3.sh](hysteria2_port_hopping_manager_v1.4.3.sh)
