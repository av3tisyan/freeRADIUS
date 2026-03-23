# FreeRADIUS 3.2 HA – configuration for Git

Template for a **two-node FreeRADIUS HA cluster**: **AD (LDAPS)**, **EAP-TTLS/PEAP**, **OU allow/deny**, **group-based VLAN** (wired), **RadSec** (2083), **BlastRADIUS** mitigation, **HA** (BGP anycast or VRRP).

**Start here:** [docs/NEW_USER_GUIDE.md](docs/NEW_USER_GUIDE.md) · **Changes:** [docs/CHANGELOG.md](docs/CHANGELOG.md)

**Deploy:** Copy `etc/freeradius/3.0/` → `/etc/freeradius/3.0/` on each node. Replace **all** placeholders (secrets, IPs, domains). See [Placeholders](#placeholders-to-replace) and [docs/BOOTSTRAP_AND_DEPLOYMENT.md](docs/BOOTSTRAP_AND_DEPLOYMENT.md).

**Public mirror:** [github.com/av3tisyan/freeRADIUS](https://github.com/av3tisyan/freeRADIUS)

---

## Repo layout

| Path | Purpose |
|------|--------|
| `etc/freeradius/3.0/` | **Deploy this** — clients, mods, `sites-available/` (canonical), `sites-enabled/` → symlinks to `default`, `inner-tunnel`, `radsec` (if symlinks are lost after copy on Windows, recreate: `ln -sf ../sites-available/NAME sites-enabled/NAME`) |
| `etc/freeradius/3.0/certs/` | CA/server scripts and `.cnf` — edit for your domain |
| `docs/` | Guides (see [Documentation](#documentation)) |
| `client-configs/` | Sanitized macOS / Windows / Linux client examples |
| `scripts/` | rsync sync, systemd drop-in, `ha-bgp-anycast/`, `ha-frr/` |

---

## Placeholders to replace

| Placeholder | Where |
|-------------|--------|
| `REPLACE_LOCALHOST_SECRET` | clients.conf — match `proxy.conf` home server if you proxy to localhost |
| `REPLACE_VPN_GATEWAY_SECRET`, `REPLACE_TEST_VPN_SECRET`, `REPLACE_WIFI_NAS_SECRET`, `REPLACE_WIRED_NAS_SECRET`, `REPLACE_VIP_SECRET` | clients.conf |
| `REPLACE_LDAP_*`, `REPLACE_AD_ROOT_CA_FILENAME` | mods-enabled/ldap |
| `REPLACE_TLS_KEY_PASSWORD_OR_EMPTY` | mods-enabled/eap, sites-available/radsec |
| `REPLACE_RADSEC_SECRET`, `REPLACE_WIFI_NAS_RADSEC_SECRET`, `REPLACE_WIRED_NAS_RADSEC_SECRET` | sites-available/radsec |
| Example **192.168.200.x** / **201.x** / **202.x** / **203.x** | clients.conf, radsec — use your real VIP and NAS subnets |
| `radius.example.com`, `YourOrg` | certs `*.cnf`, xpextensions |

---

## Quick deploy

1. Copy `etc/freeradius/3.0/` to each node (or rsync — [docs/RSYNC_HA_SYNC.md](docs/RSYNC_HA_SYNC.md)).
2. On the server, ensure `sites-enabled/` contains symlinks to `default`, `inner-tunnel`, `radsec` (this repo already does).
3. Replace placeholders; generate certs; set LDAP password and secrets ([BOOTSTRAP_AND_DEPLOYMENT.md](docs/BOOTSTRAP_AND_DEPLOYMENT.md)).
4. Test: `freeradius -XC` or `freeradius -fxx -l stdout`; enable `freeradius.service`.
5. Point NAS devices at VIP or node IPs (UDP **1812/1813**, or TCP **2083** for RadSec).

---

## Security & HA

- **BlastRADIUS:** `require_message_authenticator = yes` on clients — NAS must send Message-Authenticator.
- **HA:** Same config on both nodes; VIP via BGP ([HA_BGP_ANYCAST_SETUP.md](docs/HA_BGP_ANYCAST_SETUP.md), [scripts/ha-bgp-anycast/](scripts/ha-bgp-anycast/)) or VRRP ([HA_FRR_VRRP_SETUP.md](docs/HA_FRR_VRRP_SETUP.md), [scripts/ha-frr/](scripts/ha-frr/)).
- **RadSec:** [RADSEC_SETUP.md](docs/RADSEC_SETUP.md) — optional; many NAS use UDP only.

---

## Push to a remote

```bash
git remote add origin https://github.com/YOUR_ORG/FreeRADIUS.git
git branch -M main
git push -u origin main
```

**Optional second remote (e.g. GitHub alongside GitLab):** `git remote add github https://github.com/USER/REPO.git` then `git push github main`. Use a **PAT** for HTTPS or SSH keys for `git@github.com:...`.

---

## Documentation

| Doc | Topic |
|-----|--------|
| [NEW_USER_GUIDE.md](docs/NEW_USER_GUIDE.md) | Overview, first-time order, index |
| [BOOTSTRAP_AND_DEPLOYMENT.md](docs/BOOTSTRAP_AND_DEPLOYMENT.md) | Certs, LDAP, deploy |
| [GROUP_VLAN_ASSIGNMENT.md](docs/GROUP_VLAN_ASSIGNMENT.md) | LDAP-Group → VLAN; switch tagging / no-guest notes |
| [CLIENT_SETUP_8021X.md](docs/CLIENT_SETUP_8021X.md) | macOS / Windows / Linux profiles |
| [WIFI_8021X_TROUBLESHOOTING.md](docs/WIFI_8021X_TROUBLESHOOTING.md) | Wi‑Fi prompts, Session-Timeout, Keychain |
| [WIRED_8021X_NOT_RESPONDING.md](docs/WIRED_8021X_NOT_RESPONDING.md) | Wired client/secret/firewall + switch CLI hints |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Service won’t start; localhost proxy secret |
| [RADSEC_SETUP.md](docs/RADSEC_SETUP.md) | RadSec testing |
| [RSYNC_HA_SYNC.md](docs/RSYNC_HA_SYNC.md) | Node 1 → Node 2 sync |
| [HA_BGP_ANYCAST_SETUP.md](docs/HA_BGP_ANYCAST_SETUP.md) | BGP anycast VIP |
| [HA_FRR_VRRP_SETUP.md](docs/HA_FRR_VRRP_SETUP.md) | VRRP VIP |
| [PFSENSE_PREFER_RADIUS_01.md](docs/PFSENSE_PREFER_RADIUS_01.md) | Prefer primary node on pfSense |
| [EAP_SECURITY_AND_MSCHAPV2.md](docs/EAP_SECURITY_AND_MSCHAPV2.md) | EAP/TLS notes |
| [CERTIFICATE_RENEWAL_GUIDE.md](docs/CERTIFICATE_RENEWAL_GUIDE.md) | Renewing certs |
| [CHANGELOG.md](docs/CHANGELOG.md) | What changed |
| [certs/README.md](etc/freeradius/3.0/certs/README.md) | Cert generation in-tree |
