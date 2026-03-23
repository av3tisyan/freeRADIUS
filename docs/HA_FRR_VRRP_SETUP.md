# FreeRADIUS HA with FRR (Layer 3 VRRP)

This guide sets up High Availability for FreeRADIUS using **FRR** (Free Range Routing) **VRRP** at Layer 3. Clients use a **Virtual IP (VIP)**; the node that holds the VIP serves RADIUS; on failure the other node takes over the VIP. **Active/standby.**

**Alternative:** For **BGP anycast** (both nodes advertise the same IP; active/active from routing), see **docs/HA_BGP_ANYCAST_SETUP.md** and **scripts/ha-bgp-anycast/**.

## Overview

| Item | Value |
|------|--------|
| **Node 1 (master)** | 192.168.200.21 – higher VRRP priority, holds VIP when up |
| **Node 2 (backup)** | 192.168.200.22 – lower priority, takes VIP when master fails |
| **VIP** | 192.168.200.100 – RADIUS server address for clients (Wi‑Fi, VPN, wired NAS) |
| **Subnet** | 192.168.200.0/24 |
| **VRRP VRID** | 23 (one per VIP; 1–255) |

**Requirements:** Linux 5.1+ (for VRRP protodown), Debian 12, FRR installed. Both nodes must be on the same L2 segment for VRRP.

---

## 1. Install FRR (both nodes)

```bash
sudo apt update
sudo apt install frr
sudo systemctl enable frr
```

Enable the VRRP daemon:

```bash
sudo sed -i 's/^vrrpd=no/vrrpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

Use integrated config (single `frr.conf`):

```bash
echo 'service integrated-vtysh-config' | sudo tee -a /etc/frr/vtysh.conf
```

---

## 2. Identify the interface and create macvlan (both nodes)

Replace `INTERFACE` with the interface that has your management IP (e.g. 192.168.200.21/22) (e.g. `ens18`, `eth0`, `enp0s3`). On many Debian/VM hosts it is **ens18**.

**On each node, create a macvlan for the VIP.** The VIP must **not** be configured on the main interface; it will live on the macvlan. VRRP virtual MAC for VRID 23 (IPv4) is `00:00:5e:00:01:17`.

**Node 1 (192.168.200.21) and Node 2 (192.168.200.22)** – run once (or at boot via a script/unit):

```bash
# Replace INTERFACE with your interface name (e.g. eth0)
INTERFACE="eth0"
VIP="192.168.200.100"
VRID="23"
# VRRP IPv4 virtual MAC: 00:00:5e:00:01:VRID
MAC="00:00:5e:00:01:$(printf '%02x' "$VRID")"

sudo ip link add vrrp4-radius link "$INTERFACE" type macvlan mode bridge
sudo ip link set dev vrrp4-radius address "$MAC"
sudo ip addr add "${VIP}/24" dev vrrp4-radius
sudo ip link set dev vrrp4-radius up
```

- **Important:** Do **not** assign 192.168.200.100 to `INTERFACE`; it must only be on the macvlan. Node 1 has 192.168.200.21/24 on `INTERFACE`, Node 2 has 192.168.200.22/24 on `INTERFACE`.
- To make this persistent across reboots, use the script below (systemd or cron @reboot) or your preferred method (netplan, etc.).

---

## 3. FRR VRRP configuration

Use the **integrated** config file `/etc/frr/frr.conf`. Merge the following into the existing config (or replace if the file is minimal).

**Node 1 (192.168.200.21) – master** – replace `eth0` with your interface:

```
frr version 9.x
frr defaults traditional
hostname freeradius-node-a
service integrated-vtysh-config
!
interface eth0
 vrrp 23 version 3
 vrrp 23 priority 110
 vrrp 23 advertisement-interval 1000
 vrrp 23 ip 192.168.200.100
!
line vty
!
```

**Node 2 (192.168.200.22) – backup** – replace `eth0` with your interface:

```
frr version 9.x
frr defaults traditional
hostname freeradius-node-b
service integrated-vtysh-config
!
interface eth0
 vrrp 23 version 3
 vrrp 23 priority 100
 vrrp 23 advertisement-interval 1000
 vrrp 23 ip 192.168.200.100
!
line vty
!
```

- **VRID 23** must match on both nodes.
- **Priority:** higher = master (110 on node1, 100 on node2).
- **vrrp 23 ip 192.168.200.100** – this IP must already exist on the macvlan (step 2).

Apply and save:

```bash
sudo vtysh -c "write mem"
sudo systemctl restart frr
```

Check:

```bash
sudo vtysh -c "show vrrp"
```

Master should show `Status (v4) Master` and the VIP; backup should show `Backup`.

---

## 4. Make macvlan creation persistent (both nodes)

Create a small script and a systemd service so the macvlan exists before FRR starts.

**Script** – `/usr/local/bin/frr-vrrp-macvlan.sh` (adjust `INTERFACE`):

```bash
#!/bin/bash
INTERFACE="eth0"
VIP="192.168.200.100"
VRID="23"
MAC="00:00:5e:00:01:$(printf '%02x' "$VRID")"
IF="vrrp4-radius"

if ip link show "$IF" &>/dev/null; then
  exit 0
fi
ip link add "$IF" link "$INTERFACE" type macvlan mode bridge
ip link set dev "$IF" address "$MAC"
ip addr add "${VIP}/24" dev "$IF"
ip link set dev "$IF" up
```

**Systemd unit** – `/etc/systemd/system/frr-vrrp-macvlan.service`:

```ini
[Unit]
Description=Create macvlan for FRR VRRP (RADIUS VIP)
Before=frr.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frr-vrrp-macvlan.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo chmod +x /usr/local/bin/frr-vrrp-macvlan.sh
sudo systemctl daemon-reload
sudo systemctl enable frr-vrrp-macvlan.service
sudo systemctl start frr-vrrp-macvlan.service
```

---

## 5. FreeRADIUS: accept requests to the VIP

Add a **client** for the VIP in `clients.conf` so RADIUS requests to 192.168.200.100 are accepted (same secret as your other RADIUS clients or a dedicated one):

```
client vip {
    ipaddr = 192.168.200.100
    proto = *
    require_message_authenticator = yes
    secret = YOUR_VIP_SECRET_SAME_AS_UNIFI_OR_OPENVPN
    shortname = vip
}
```

Use the same secret as your Wi‑Fi/VPN NAS clients if they will point to the VIP. Reload config or restart FreeRADIUS on both nodes.

---

## 6. Point clients to the VIP

- **Wi‑Fi / VPN / other NAS:** Set the RADIUS server IP to **192.168.200.100** (and the same shared secret as in `clients.conf` for the VIP or the existing client you use).
- No need to point to 192.168.200.21 or 192.168.200.22; the VIP moves with the active node.

---

## 7. Sync FreeRADIUS config between nodes (optional)

Keep config (and optionally certs) in sync so both nodes behave the same:

```bash
# From node1 to node2 (run from node1)
rsync -avz --delete /etc/freeradius/3.0/ root@192.168.200.22:/etc/freeradius/3.0/
```

Exclude or handle secrets (LDAP password, client secrets) as needed. After sync, restart or reload FreeRADIUS on the other node if required.

---

## 8. Checklist

| Step | Node 1 (192.168.200.21) | Node 2 (192.168.200.22) |
|------|----------------------|------------------------|
| Install FRR | `apt install frr`, enable `vrrpd` | Same |
| Create macvlan | Run script / unit for `vrrp4-radius` with 192.168.200.100/24 | Same |
| FRR config | `frr.conf` with interface, vrrp 23, **priority 110** | Same but **priority 100** |
| FreeRADIUS | clients.conf includes client for 192.168.200.100 | Same (sync or copy) |
| Clients (Wi‑Fi, VPN, etc.) | — | Set RADIUS server to **192.168.200.100** |

---

## 9. Troubleshooting

- **VIP not responding:** Ensure macvlan is up (`ip addr show vrrp4-radius`) and FRR shows Master on one node (`show vrrp`).
- **Both nodes Master:** Different priorities; both must see VRRP adverts (same L2, no firewall blocking VRRP).
- **VRRP adverts:** Protocol uses multicast; allow it between 192.168.200.21 and 192.168.200.22 if you have ACLs/firewall.

**Zebra/mgmtd errors at startup:** Messages like `Error notifying for datastore path ... /interface[name="ens18"]` and `can't send message on closed connection` are common when FRR starts; they are internal backplane/notification noise and do not affect VRRP. You can ignore them if `show vrrp` shows the correct state and the VIP responds.
