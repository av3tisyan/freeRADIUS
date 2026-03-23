# Changelog (repo)

## Unreleased

- **Vendor-neutral:** `ca.cnf` comment and MDM examples no longer reference a specific organization or product.
- **Docs consolidated:** [WIFI_8021X_TROUBLESHOOTING.md](WIFI_8021X_TROUBLESHOOTING.md) (was two Wi‑Fi docs); [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (service start + localhost proxy); extra VLAN/segmentation and tagged-port notes merged into [GROUP_VLAN_ASSIGNMENT.md](GROUP_VLAN_ASSIGNMENT.md); wired switch CLI hints in [WIRED_8021X_NOT_RESPONDING.md](WIRED_8021X_NOT_RESPONDING.md). README slimmed; publishing notes folded into README.
- **Config layout:** `sites-available/` holds **default**, **inner-tunnel**, **radsec**; `sites-enabled/` uses **symlinks** only. Removed duplicate `frr.conf.radius-01/02` (use **frr.conf.node1/node2**).
- Example **private IP plan** (**192.168.200/201/202/203**); generic NAS shortnames and placeholders (see README).
- Example AD groups/VLANs: **RADIUS-Corp** (300), **RADIUS-SiteA/B**, **RADIUS-Guest**, default **1000**; **DC=example,DC=com**.

## Earlier (accumulated)

### BGP anycast (FRR)

- **FRR:** `scripts/ha-bgp-anycast/frr.conf.node1`, `frr.conf.node2` (AS 65004, optional `frr.conf.node1.with-med`).
- **HA_BGP_ANYCAST_SETUP.md**, **PFSENSE_PREFER_RADIUS_01.md**.

### FreeRADIUS

- **default** post-auth: `Session-Timeout := 86400` for Wi‑Fi NAS (`Client-Shortname =~ /wifi-nas/`).
- **WIFI_8021X_TROUBLESHOOTING.md** (client/AP/session behavior).

### Clients (802.1X)

- **client-configs/**, **CLIENT_SETUP_8021X.md**.

### README

- Placeholders table, doc index, HA/RadSec pointers.
