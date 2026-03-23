# FreeRADIUS HA – New User Guide & Documentation Overview

This guide is the **starting point for anyone new** to this repository. It explains what the project is, how the pieces fit together, and where to find detailed instructions.

---

## 1. What is this project?

This repository contains **configuration and documentation** for a **two-node FreeRADIUS high-availability (HA) cluster**. It is intended for teams that need:

- **RADIUS authentication** for VPN gateways, wireless (Wi‑Fi controller/APs), or wired 802.1X.
- **Active Directory (AD)** as the user store, over **LDAPS**.
- **EAP-TTLS / PEAP** with inner PAP (username/password over TLS; no client certificates for typical WiFi).
- **RadSec** (RADIUS over TLS on TCP 2083) for secure RADIUS to upstream devices (e.g. pfSense).
- **Two servers** so that if one fails, the other can serve requests (HA).
- **A single IP (VIP)** that clients use, with traffic going to whichever node is currently active (BGP anycast or VRRP).

**You get:** Template config files under `etc/freeradius/3.0/`, scripts for sync and HA, and step-by-step docs. **You must:** Replace all placeholders (secrets, IPs, domain names) and follow the deployment docs on your own infrastructure.

---

## 2. High-level architecture

```
                    NAS (VPN, Wi‑Fi, firewall, etc.)
                                    │
                    ┌───────────────┴───────────────┐
                    │   RADIUS (UDP 1812/1813 or    │
                    │   RadSec TCP 2083)             │
                    └───────────────┬───────────────┘
                                    │
                         ┌──────────┴──────────┐
                         │   VIP (anycast or   │  ← Single address clients use
                         │   VRRP)             │
                         └──────────┬──────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
       ┌──────┴──────┐       ┌──────┴──────┐              │
       │  Node 1     │       │  Node 2     │              │
       │ (freeradius-node-a) │       │ (freeradius-node-b) │              │
       │             │  rsync │             │              │
       │ FreeRADIUS  │ ──────► FreeRADIUS  │              │
       │ /etc/       │        /etc/        │              │
       │ freeradius/ │        freeradius/  │              │
       └──────┬──────┘       └──────┬──────┘              │
              │                     │                     │
              └─────────────────────┼─────────────────────┘
                                    │
                         ┌──────────┴──────────┐
                         │  Active Directory  │  LDAPS
                         │  (DC01, DC02)     │
                         └───────────────────┘
```

- **Node 1** – Primary; you edit config here. Config is synced to Node 2 (e.g. via rsync on every restart or cron).
- **Node 2** – Standby; receives the same config so both nodes behave identically.
- **VIP** – One IP (or hostname) for RADIUS. BGP anycast or VRRP ensures that IP is served by the active node.
- **NAS** – Network Access Servers (VPN gateways, wireless controllers, firewalls) that send RADIUS requests to the VIP or directly to a node.

**At a glance:** EAP-TTLS + inner PAP to AD; anonymous outer identity; group→VLAN in **inner-tunnel** (or wired-only logic in **default**); example VLANs **RADIUS-Corp** (300), **RADIUS-SiteA/B**, **RADIUS-Guest**, default **1000**. Guest/restricted VLAN is enforced on the switch/firewall, not only by RADIUS.

---

## 3. Repository layout (what’s in the repo)

| Path | Purpose |
|------|--------|
| **Config (deploy this)** | |
| `etc/freeradius/3.0/` | **Copy to `/etc/freeradius/3.0/` on each node.** All FreeRADIUS config: clients, EAP, LDAP, sites, certs. |
| `etc/freeradius/3.0/clients.conf` | RADIUS clients (localhost, NAS, VIP). Replace IPs and secrets. |
| `etc/freeradius/3.0/mods-enabled/eap` | EAP-TTLS/PEAP, TLS 1.2. Replace TLS key password. |
| `etc/freeradius/3.0/mods-enabled/ldap` | LDAPS to AD. Replace servers, bind DN, base DN, password, CA. |
| `etc/freeradius/3.0/sites-available/` | Canonical **default**, **inner-tunnel**, **radsec** definitions. |
| `etc/freeradius/3.0/sites-enabled/` | Symlinks to the three sites above. RadSec = TCP 2083. |
| `etc/freeradius/3.0/certs/` | Scripts and .cnf for CA and server certs. Edit for your domain. |
| **Documentation** | |
| [NEW_USER_GUIDE.md](NEW_USER_GUIDE.md) | **This file.** Overview and entry point for new users. |
| [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md) | Certificates, LDAP password, BlastRADIUS, bootstrap order, firewall/VPN notes. |
| [RSYNC_HA_SYNC.md](RSYNC_HA_SYNC.md) | Sync config from Node 1 to Node 2: manual, cron, or “on every restart” (systemd drop-in). |
| [RADSEC_SETUP.md](RADSEC_SETUP.md) | RadSec setup, testing, pfSense CA import. |
| [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md) | BGP anycast for VIP (FRR). |
| [HA_FRR_VRRP_SETUP.md](HA_FRR_VRRP_SETUP.md) | VRRP for VIP (FRR). |
| [EAP_SECURITY_AND_MSCHAPV2.md](EAP_SECURITY_AND_MSCHAPV2.md) | EAP and TLS security notes. |
| [CERTIFICATE_RENEWAL_GUIDE.md](CERTIFICATE_RENEWAL_GUIDE.md) | Certificate renewal. |
| [GROUP_VLAN_ASSIGNMENT.md](GROUP_VLAN_ASSIGNMENT.md) | LDAP-Group → VLAN; tagging / no-guest notes. |
| [CLIENT_SETUP_8021X.md](CLIENT_SETUP_8021X.md) | End-user Wi‑Fi / wired profiles. |
| [WIFI_8021X_TROUBLESHOOTING.md](WIFI_8021X_TROUBLESHOOTING.md) | Random prompts, Keychain / Remember. |
| [WIRED_8021X_NOT_RESPONDING.md](WIRED_8021X_NOT_RESPONDING.md) | Wired “server not responding”. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Service start failures; localhost proxy secret. |
| [../etc/freeradius/3.0/certs/README.md](../etc/freeradius/3.0/certs/README.md) | Certificate generation and renewal in the certs dir. |
| **Scripts** | |
| `scripts/sync-freeradius-to-node2.sh` | Rsync script: syncs `/etc/freeradius/3.0/` to Node 2. Used by cron or systemd. |
| `scripts/restart-freeradius-and-sync.sh` | Restart FreeRADIUS, then run sync (manual “restart and push”). |
| `scripts/systemd/freeradius.service.d/sync-after-restart.conf` | Drop-in: run sync after every `freeradius` start/restart (run as root via `+`). |
| `scripts/ha-bgp-anycast/` | FRR BGP config examples and anycast script. |
| `scripts/ha-frr/` | VRRP-related scripts if used. |

---

## 4. Key concepts for new users

- **Placeholders** – Every file under `etc/freeradius/3.0/` uses placeholders like `REPLACE_LDAP_BIND_DN`, `REPLACE_VPN_GATEWAY_SECRET`, example IPs. You **must** replace them with your real values before starting FreeRADIUS. See the main [README](../README.md#placeholders-to-replace) table.
- **Single deploy path** – Only `etc/freeradius/3.0/` is meant to be deployed. Copy it to `/etc/freeradius/3.0/` on each node. Nothing else in the repo is “installed” except the sync scripts and systemd drop-in if you use “sync on restart.”
- **Node 1 vs Node 2** – Node 1 is where you edit config. Node 2 gets a copy (rsync). Sync direction is always Node 1 → Node 2.
- **VIP** – The single IP (or hostname) that NAS devices use for RADIUS. Implemented with BGP anycast or VRRP; see [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md) or [HA_FRR_VRRP_SETUP.md](HA_FRR_VRRP_SETUP.md).
- **BlastRADIUS** – All clients in this config use `require_message_authenticator = yes`. Do not disable it; ensure your NAS send Message-Authenticator.
- **Sites** – Edit **`sites-available/`** (default, inner-tunnel, radsec). **`sites-enabled/`** in this repo is **symlinks** to those files; recreate them on the server if your copy step does not preserve links.

---

## 5. First-time setup: order of operations

Follow this order when setting up from scratch.

| Step | What to do | Where it’s documented |
|------|------------|------------------------|
| 1 | Clone the repo and read the [README](../README.md) and this guide. | [README.md](../README.md), this file |
| 2 | Replace **all placeholders** in `etc/freeradius/3.0/` (clients, LDAP, EAP, RadSec, cert .cnf, IPs). | [README – Placeholders](../README.md#placeholders-to-replace) |
| 3 | Copy `etc/freeradius/3.0/` to **Node 1** at `/etc/freeradius/3.0/`. | [README – Quick deploy](../README.md#quick-deploy) |
| 4 | On Node 1: generate or install certs, set LDAP password, set permissions (e.g. `chown freerad`, `chmod 640` on keys). | [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md) |
| 5 | Test on Node 1: `freeradius -C` (or `radiusd -XC`), then `radtest`; start `freeradius.service`. | [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md) |
| 6 | Deploy config to **Node 2** (copy or rsync). Set ownership and restart FreeRADIUS on Node 2. | [RSYNC_HA_SYNC.md](RSYNC_HA_SYNC.md) |
| 7 | Configure **sync** so Node 2 stays updated: either “sync on every restart” (drop-in) or cron or manual. | [RSYNC_HA_SYNC.md](RSYNC_HA_SYNC.md) |
| 8 | Configure **VIP**: BGP anycast or VRRP so clients use one IP. | [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md), [HA_FRR_VRRP_SETUP.md](HA_FRR_VRRP_SETUP.md) |
| 9 | If using **RadSec**: configure clients, TLS, and (e.g.) pfSense CA import. | [RADSEC_SETUP.md](RADSEC_SETUP.md) |
| 10 | Point your NAS (VPN, Wi‑Fi, firewall) at the VIP or node IPs (UDP 1812/1813 or RadSec 2083). | [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md), [RADSEC_SETUP.md](RADSEC_SETUP.md) |

---

## 6. Documentation index (when to read what)

| Document | When to read it |
|----------|------------------|
| [README.md](../README.md) | First. Repo layout, placeholders, quick deploy, security and HA summary. |
| [NEW_USER_GUIDE.md](NEW_USER_GUIDE.md) | You are here. Overview, architecture, first-time order, doc index. |
| [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md) | When installing or reinstalling: certs, LDAP password, BlastRADIUS, bootstrap steps, firewall/VPN, EAP-TTLS Wi‑Fi client setup. |
| [RSYNC_HA_SYNC.md](RSYNC_HA_SYNC.md) | When you need to keep Node 2 in sync with Node 1: manual rsync, cron, or “sync on every restart” (systemd drop-in), passwordless SSH/sudo, troubleshooting. |
| [RADSEC_SETUP.md](RADSEC_SETUP.md) | When you use RadSec (TCP 2083): setup, testing, pfSense CA import. |
| [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md) | When you use BGP anycast for the RADIUS VIP (FRR). |
| [HA_FRR_VRRP_SETUP.md](HA_FRR_VRRP_SETUP.md) | When you use VRRP for the RADIUS VIP (FRR). |
| [EAP_SECURITY_AND_MSCHAPV2.md](EAP_SECURITY_AND_MSCHAPV2.md) | When you need EAP/TLS or MSCHAPv2 security details. |
| [CERTIFICATE_RENEWAL_GUIDE.md](CERTIFICATE_RENEWAL_GUIDE.md) | When renewing server or CA certificates. |
| [GROUP_VLAN_ASSIGNMENT.md](GROUP_VLAN_ASSIGNMENT.md) | Group-based VLAN and switch-side tagging. |
| [CLIENT_SETUP_8021X.md](CLIENT_SETUP_8021X.md) | macOS / Windows / Linux 802.1X client setup. |
| [WIFI_8021X_TROUBLESHOOTING.md](WIFI_8021X_TROUBLESHOOTING.md) | Wi‑Fi credential prompts and saved password issues. |
| [WIRED_8021X_NOT_RESPONDING.md](WIRED_8021X_NOT_RESPONDING.md) | Wired RADIUS client/secret/firewall. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Service won’t start; Message-Authenticator on localhost proxy. |
| [../etc/freeradius/3.0/certs/README.md](../etc/freeradius/3.0/certs/README.md) | When generating or regenerating certs in the certs directory. |

---

## 7. Quick reference

**Config location on each node:**  
`/etc/freeradius/3.0/`

**Test config (no start):**  
`freeradius -C`  
(or `radiusd -XC` on some systems)

**Restart FreeRADIUS:**  
`sudo systemctl restart freeradius`

**If using “sync on every restart”:**  
After the above restart, sync runs automatically. Log:  
`sudo tail -f /var/log/freeradius/rsync-sync.log`

**Manual sync (from Node 1):**  
`sudo /usr/local/bin/sync-freeradius-to-node2.sh`  
(After installing the script and setting REMOTE_USER / REMOTE_HOST.)

**RADIUS ports:**  
- UDP 1812 (auth), 1813 (accounting); RadSec TCP 2083.

**Secrets:**  
Never commit real secrets. Replace placeholders on the server only (or via a secrets manager).

---

## 8. Summary

- This repo is a **template** for a **two-node FreeRADIUS HA cluster** with AD (LDAPS), EAP-TTLS/PEAP, RadSec, and BlastRADIUS mitigation.
- Deploy **only** `etc/freeradius/3.0/` to `/etc/freeradius/3.0/` on each node; replace all placeholders first.
- Keep Node 2 in sync with Node 1 using the **rsync** script (on restart, cron, or manual); see [RSYNC_HA_SYNC.md](RSYNC_HA_SYNC.md).
- Use **BGP anycast** or **VRRP** for a single VIP that NAS use; see [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md) or [HA_FRR_VRRP_SETUP.md](HA_FRR_VRRP_SETUP.md).
- Use the **documentation index** (section 6) above to jump to the right doc for each task.

New users should read the [README](../README.md), then this [NEW_USER_GUIDE](NEW_USER_GUIDE.md), then follow the **first-time setup order** (section 5) and the linked docs for each step.
