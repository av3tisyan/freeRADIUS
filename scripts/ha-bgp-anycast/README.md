# BGP Anycast for FreeRADIUS VIP (192.168.200.100)

Both nodes advertise **192.168.200.100/32** via BGP; the upstream router sends traffic to the best path. Full guide: **docs/HA_BGP_ANYCAST_SETUP.md**.

**Files:**
- **anycast-address-on-lo.sh** – add 192.168.200.100/32 on `lo`; copy to `/usr/local/bin/`, run at boot.
- **anycast-address-on-lo.service** – systemd unit; copy to `/etc/systemd/system/`, enable.
- **daemons** – example snippet for `/etc/frr/daemons` (bgpd=yes, vtysh_enable=yes).
- **frr.conf.node1** – FRR for **freeradius-node-a** (192.168.200.21). Copy to `/etc/frr/frr.conf` on that host.
- **frr.conf.node2** – FRR for **freeradius-node-b** (192.168.200.22). Same BGP policy as node1 (no MED) for equal-cost failover.
- **frr.conf.node1.with-med** – optional: freeradius-node-a with MED 50 if you want to prefer it on the router (see docs/PFSENSE_PREFER_RADIUS_01.md).

**Requirement:** Upstream L3 device must run BGP and peer with both 192.168.200.21 and 192.168.200.22 (Remote AS 65004). Do **not** run VRRP and BGP anycast for the same IP at once.
