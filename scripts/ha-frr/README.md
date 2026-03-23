# HA with FRR VRRP (RADIUS VIP)

Scripts and example configs for FreeRADIUS HA using FRR VRRP and VIP **192.168.200.100**.

- **Node 1:** 192.168.200.21 (master, priority 110)
- **Node 2:** 192.168.200.22 (backup, priority 100)
- **VIP:** 192.168.200.100

Full steps: see **docs/HA_FRR_VRRP_SETUP.md**.

**Files:**
- `frr-vrrp-macvlan.sh` – create macvlan for VIP; copy to `/usr/local/bin/`, set `INTERFACE`, enable via systemd.
- `frr-vrrp-macvlan.service` – systemd unit; copy to `/etc/systemd/system/`, set `RADIUS_VRRP_INTERFACE` or edit script.
- `frr.conf.node1` / `frr.conf.node2` – example FRR VRRP snippets; merge into `/etc/frr/frr.conf` and replace `eth0` with your interface.
