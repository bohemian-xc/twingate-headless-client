# Twingate Headless Client for WSL2 with Windows Host Routing

This project enables you to run the Twingate headless client inside WSL2 (via Docker Compose) and forward Windows host traffic through the Twingate tunnel. It consists of:

1. **A Docker Compose setup** to run the Twingate client in WSL2.
2. **A PowerShell script** to manage Windows static routes, forwarding selected traffic from the Windows host to WSL2.

---

## Part 1: Configure and Run Twingate Headless Client in WSL2

### Prerequisites

- WSL2 with a Linux distribution (e.g., Ubuntu)
- Docker and Docker Compose installed in WSL2
- A valid Twingate service key (JSON file)

### Setup Steps

1. **Clone this repository in your WSL2 environment:**

   ```bash
   git clone <your-repo-url>
   cd twingate-headless-client
   ```

2. **Place your Twingate service key:**

   - Copy your `service-key.json` into `./app/service-key/service-key.json`.

3. **Review and edit `compose.yml` as needed:**

   - Set environment variables:
     - `SERVICE_KEY`: Path to your service key JSON.
     - `TG_HST_IFACE`: Name of the WSL2 interface that connects to the Windows host (default: `eth0`).
     - `TG_WAN_IFACE`: Name of the Twingate tunnel interface (e.g., `sdwan0`, `wg0`, or `tun0`).
     - `LOG_FILE`, `LOG_ROTATE_HOURS`, etc.

   - Example snippet from `compose.yml`:
     ```yaml
     environment:
       - 'SERVICE_KEY=/app/service-key/service-key.json'
       - 'TG_HST_IFACE=eth0'
       - 'TG_WAN_IFACE=sdwan0'
       - 'LOG_FILE=/var/log/twingate-client.log'
       - 'LOG_ROTATE_HOURS=24'
       - 'TZ=Asia/Singapore'
     ```

4. **Build and start the container:**

   ```bash
   docker compose up -d --build
   ```

5. **Check logs:**

   ```bash
   docker logs twingate-headless-client
   ```

---

## Part 2: Configure Windows Host-to-WSL2 Routing

This step ensures that selected Windows host traffic is routed through the Twingate tunnel running in WSL2.

### Prerequisites

- PowerShell (run as Administrator)
- The `host-to-wsl-routing.ps1` script and a configuration file (`host-to-wsl.json`)

### Setup Steps

1. **Create/Edit `host-to-wsl.json` in the `host` directory:**

   Example:
   ```json
   [
     {
       "Distro": "Ubuntu-22.04",
       "Subnet": "10.20.30.0",
       "Mask": "255.255.255.0",
       "Metric": 5
     }
   ]
   ```
   - `Distro`: Name of your WSL2 distribution (as shown by `wsl -l`).
   - `Subnet`/`Mask`: The network you want to route via WSL2/Twingate.
   - `Metric`: Route metric (lower is preferred).

2. **Open PowerShell as Administrator and run:**

   ```powershell
   cd path\to\twingate-headless-client\host
   .\host-to-wsl-routing.ps1 -Mode add
   ```

   - This will add (or update) routes for each entry in your config.
   - To remove routes, run:
     ```powershell
     .\host-to-wsl-routing.ps1 -Mode delete
     ```

3. **Verify routes:**

   ```powershell
   route print
   ```

---

## Troubleshooting

- **Twingate not connecting?**  
  Check the container logs and ensure your service key is valid.
- **Routes not working?**  
  Ensure the WSL2 instance is running and the correct IP is detected by the script.
- **Firewall issues?**  
  Make sure Windows Firewall allows traffic between the host and WSL2.

---

## File Overview

- `compose.yml` — Docker Compose file for Twingate client.
- `app/entrypoint.sh` — Entrypoint script for the container (handles forwarding, logging, etc.).
- `host/host-to-wsl-routing.ps1` — PowerShell script to manage Windows routes.
- `host/host-to-wsl.json` — Configuration for which subnets to route via WSL2.

---

## References

- [Twingate Documentation](https://docs.twingate.com/)
- [WSL2 Networking](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Docker Compose](https://docs.docker.com/compose/)

---