# FreeRADIUS HA with BGP Anycast (Debian)

This guide sets up **BGP anycast** for the RADIUS VIP on **Debian**: both nodes advertise the same VIP (e.g. **192.168.200.100/32**) via BGP. Replace the example IPs and AS numbers with your own node/VIP/subnet and BGP AS. Commands use `apt` and systemd; persistence uses a systemd unit or `/etc/network/interfaces`. The network routes traffic to the “best” path (one or both nodes). If one node or path fails, BGP withdraws that path and traffic goes to the other node. This is **active/active** from a routing perspective (both nodes can receive traffic depending on topology).

## Overview

| Item | Value |
|------|--------|
| **Node 1** | 192.168.200.21 – advertises 192.168.200.100/32 via BGP |
| **Node 2** | 192.168.200.22 – advertises 192.168.200.100/32 via BGP |
| **Anycast IP** | 192.168.200.100 – same address on both nodes; clients use this as RADIUS server |
| **Subnet** | 192.168.200.0/24 |
| **Upstream BGP peer** | Your L3 router/switch (e.g. 192.168.200.1); must peer with both nodes |

**Requirements:** FRR with **bgpd**, an upstream router (or L3 switch) that runs BGP and can peer with both radius nodes. Both nodes must have 192.168.200.100/32 configured locally (e.g. on loopback) so BGP can advertise it.

---

## 1. Install FRR and enable BGP (both nodes)

```bash
sudo apt update
sudo apt install frr
sudo systemctl enable frr
```

Enable **bgpd** (and zebra; usually already on):

```bash
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

Use integrated config:

```bash
echo 'service integrated-vtysh-config' | sudo tee -a /etc/frr/vtysh.conf
```

---

## 2. Assign the anycast address on both nodes

The anycast IP **192.168.200.100/32** must exist on each node so BGP can advertise it. Use a **loopback** so it is always up and not tied to a single interface.

**On both freeradius-node-a and freeradius-node-b:**

```bash
# Create loopback alias with the anycast address (persist across reboots via netplan/systemd/ifup)
sudo ip addr add 192.168.200.100/32 dev lo
```

**Make it persistent on Debian:**

- **Recommended:** Use the systemd unit from **scripts/ha-bgp-anycast/** (copy `anycast-address-on-lo.sh` to `/usr/local/bin/`, run `sudo chmod +x /usr/local/bin/anycast-address-on-lo.sh`, copy `anycast-address-on-lo.service` to `/etc/systemd/system/`, then `sudo systemctl daemon-reload && sudo systemctl enable --now anycast-address-on-lo.service`).
- **Alternative – `/etc/network/interfaces`:** Add a stanza for loopback with the anycast address:`

```bash
# In /etc/network/interfaces (Debian), add or extend the lo stanza:
auto lo
iface lo inet loopback
    address 127.0.0.1/8
    address 192.168.200.100/32
```

Then `sudo ifup lo` or reboot. If `lo` is already managed by systemd-networkd or another tool, use the systemd unit instead.

---

## 3. BGP configuration (FRR)

Replace placeholders with your real values:

- **Upstream peer IP** – e.g. your router 192.168.200.1
- **Upstream peer AS** – e.g. 65000
- **Radius node AS** – same for both nodes (e.g. 65004)

**Node 1 (192.168.200.21)** – `/etc/frr/frr.conf` (merge with existing, or replace). See **scripts/ha-bgp-anycast/frr.conf.node1**:

```
frr version 10.3
frr defaults traditional
hostname freeradius-node-a
log syslog informational
no ip forwarding
no ipv6 forwarding
service integrated-vtysh-config
!
router bgp 65004
 bgp router-id 192.168.200.21
 no bgp ebgp-requires-policy
 neighbor 192.168.200.1 remote-as 65000
 !
 address-family ipv4 unicast
  network 192.168.200.100/32
 exit-address-family
exit
!
line vty
!
```

**Node 2 (192.168.200.22)** – same, but `router-id` and hostname different. See **scripts/ha-bgp-anycast/frr.conf.node2**:

```
frr version 10.3
frr defaults traditional
hostname freeradius-node-b
log syslog informational
no ip forwarding
no ipv6 forwarding
service integrated-vtysh-config
!
router bgp 65004
 bgp router-id 192.168.200.22
 no bgp ebgp-requires-policy
 neighbor 192.168.200.1 remote-as 65000
 !
 address-family ipv4 unicast
  network 192.168.200.100/32
 exit-address-family
exit
!
line vty
!
```

**Daemons:** Ensure `bgpd=yes` and `vtysh_enable=yes` in `/etc/frr/daemons` (see **scripts/ha-bgp-anycast/daemons** for an example snippet).

**If your router uses a different peer IP or AS,** change `neighbor ... remote-as` and the router-id accordingly. The important part is that **both** nodes advertise `network 192.168.200.100/32`.

---

## 4. Upstream router (L3 switch / router)

The device that has 192.168.200.1 (or your chosen peer) must:

1. **Peer with both** radius nodes via BGP (neighbors 192.168.200.21 and 192.168.200.22, in AS 65004).
2. **Advertise** its routes to the radius nodes as needed (so radius nodes can reach the rest of the network if required).
3. **Receive** 192.168.200.100/32 from both peers; it will install the best path(s). With equal cost it may load-balance; with different MED/local-pref it will prefer one path.

Example (Cisco-style; adapt to your platform):

```
router bgp 65000
 neighbor 192.168.200.21 remote-as 65004
 neighbor 192.168.200.22 remote-as 65004
 !
 address-family ipv4
  neighbor 192.168.200.21 activate
  neighbor 192.168.200.22 activate
  network 192.168.200.0 mask 255.255.255.0
 exit-address-family
```

### 4.1 pfSense as upstream router

**Important:** The router must **accept** the prefix 192.168.200.100/32 **from both** radius neighbors. If the BGP summary shows **PfxRcd 0** or **(Policy)** for 192.168.200.21/192.168.200.22, the router is not installing the route—usually because an **inbound route-map or prefix-list** is blocking it. For both neighbors, set **Inbound Route Map** to one that **permits** the route (e.g. **allow-all**), or remove any restrictive inbound filter so the RADIUS anycast prefix is accepted.

If your upstream router is **pfSense** (with the FRR package):

1. **Install FRR:** System → Package Manager → install **FRR** (if not already). Enable **BGP** in Services → FRR → Global → set your **AS** (e.g. **65000**). Apply.

2. **Allow route exchange:** pfSense FRR does not exchange routes with peers by default; you must attach a filter. In **Services → FRR → Route Maps**, add a route map: Name **allow-all**, Action **Permit**, Sequence **100** (no match/set needed). This permits all routes in/out. For stricter security you can later use prefix lists to allow only 192.168.200.100/32 inbound and 192.168.200.0/24 outbound.

3. **Add BGP neighbors:** **Services → FRR → BGP → Neighbors**. Add two neighbors:
   - **Neighbor 1:** Name/Address **192.168.200.21**, Remote AS **65004**, Update Source = **Local Source** **192.168.200.1** (or the interface IP that faces the radius subnet). Under **Peer Filtering**, set **Inbound Route Map** and **Outbound Route Map** to **allow-all** (so you receive 192.168.200.100/32 and can advertise 192.168.200.0/24 if needed).
   - **Neighbor 2:** Name/Address **192.168.200.22**, Remote AS **65004**, Update Source = **192.168.200.1**, same route map **allow-all** for inbound/outbound.

4. **Networks (optional):** In **Services → FRR → BGP → Networks**, add **192.168.200.0/24** if you want the radius nodes to learn the subnet from pfSense.

5. Apply and restart FRR if needed. Verify in **Services → FRR → BGP → Neighbors** that both peers are **Established**, and in **Routes** that **192.168.200.100/32** is received from both.

No special config is required on the radius nodes for “anycast” beyond advertising the same prefix from both.

### 4.2 Prefer one RADIUS node (so failover works: SSH goes to the other server)

If both paths are equal, pfSense load-balances and some traffic (e.g. SSH) can still go to the node where you stopped FRR. To make pfSense use **one** server (e.g. server1) when it's up, and only use server2 when server1 is down:

**On pfSense:**

1. **Prefix list (optional):** **Services → FRR** → find **Prefix Lists** (may be under Global or a separate tab). Add: Name **radius-anycast**, Sequence **10**, Action **Permit**, Network **192.168.200.100/32**. Save.

2. **Route map:** **Services → FRR → Route Maps**. Add: Name **prefer-freeradius-node-a**, Sequence **10**, Action **Permit**. In **Local Preference**, choose **Set** and value **200**. If you created the prefix list, set **Match Prefix List** to **radius-anycast**; otherwise leave match empty (affects all routes from the neighbor). Save.

3. **Apply to preferred neighbor only:** **Services → FRR → BGP → Neighbors**. Edit neighbor **192.168.200.21** (server1). Under **Peer Filtering**, set **Inbound Route Map** to **prefer-freeradius-node-a**. Leave the other neighbor (192.168.200.22) without this route map. Save.

4. Apply/Save and restart FRR if prompted. Result: routes from 192.168.200.21 get local-pref 200; from 192.168.200.22 stay 100. So pfSense uses server1 when both are up. When you stop FRR on server1, that path is withdrawn and all traffic (ping and SSH) goes to server2.

---

## 5. FreeRADIUS: accept requests to the anycast IP

Both nodes must accept RADIUS requests to 192.168.200.100. In **clients.conf** (same as for VRRP) add:

```
client vip {
    ipaddr = 192.168.200.100
    proto = *
    require_message_authenticator = yes
    secret = YOUR_VIP_SECRET
    shortname = vip
}
```

Sync **clients.conf** (and the rest of the config) to both nodes. Use the same secret for the VIP on both.

---

## 6. Point clients to the anycast IP

- **Wi‑Fi / VPN / other NAS:** Set RADIUS server to **192.168.200.100**. The network will deliver packets to whichever node BGP chose (or load-balance if ECMP).

---

## 7. Optional: prefer one node (MED or local-preference)

To prefer one radius node when both paths are available, adjust path selection on the **upstream router** (not on the radius nodes):

- **MED (Multi-Exit Discriminator):** Set a lower MED in the BGP update from the preferred radius node so the router prefers that path. This requires the radius node to send MED (e.g. `set metric` in a route-map outbound on the preferred node).
- **Local-preference:** On the router, set higher local-preference for the path from the preferred neighbor.

Example (FRR on **preferred** radius node – e.g. node1 – set MED lower):

```
router bgp 65001
 ...
 address-family ipv4 unicast
  network 192.168.200.100/32
  neighbor 192.168.200.1 route-map SET_MED out
 exit-address-family
!
route-map SET_MED permit 10
 set metric 50
!
```

On the other node, don’t set MED (or set higher, e.g. 100). The router will prefer the path with lower MED.

---

## 8. Failover: why SSH (or traffic) still goes to the stopped node

If you stop FRR on one node, BGP withdraws that path and the router should send all traffic to the other node. Two things can prevent that:

1. **ECMP (equal-cost paths)** – If the router has two next-hops for 192.168.200.100/32 (via server1 and server2), it may load-balance. So some connections (e.g. SSH) still go to the node where you stopped FRR. That node still has 192.168.200.100 on loopback, so it accepts the connection. **Fix:** Prefer a single path when both are up (e.g. set higher local-preference or lower MED for one neighbor on the router). Then when that path is withdrawn, the other is used and all traffic goes to the remaining node.

2. **Convergence delay** – After stopping FRR, wait 2–3 minutes for the BGP session to be declared down (hold timer) and the route removed. Then try a **new** SSH; it should go to the other node.

**Optional:** When taking a node out of service, remove the anycast IP so it no longer accepts traffic to 192.168.200.100 even if some packets still arrive:

```bash
sudo ip addr del 192.168.200.100/32 dev lo
```

Add it back when the node is back in service (e.g. run the anycast script again or restart the systemd unit).

---

## 9. Checklist

| Step | Node 1 | Node 2 | Upstream router |
|------|--------|--------|------------------|
| Anycast on lo | `ip addr add 192.168.200.100/32 dev lo` (persist) | Same | — |
| FRR bgpd | Enable, `network 192.168.200.100/32`, neighbor to router | Same | — |
| BGP peer | — | — | Peer with 192.168.200.21 and 192.168.200.22 |
| FreeRADIUS | clients.conf has client for 192.168.200.100 | Same | — |
| Clients | — | — | Point RADIUS to 192.168.200.100 |

---

## 10. Troubleshooting: “When I stop server-01, server-02 doesn’t respond”

If both configs are identical but traffic to the anycast IP (192.168.200.100) stops working when server-01 is down, check the following **on both nodes and on the router**.

### 10.1 Server-02 must have the anycast IP on loopback

Traffic to 192.168.200.100 is delivered to server-02’s **physical interface** (next-hop). The kernel only accepts it if **192.168.200.100** is configured on that host.

**On server-02 run:**

```bash
ip addr show lo
```

You must see **192.168.200.100/32** on `lo`. If not, add it (and make it persistent):

```bash
sudo ip addr add 192.168.200.100/32 dev lo
```

Use the same method you use on server-01 (systemd unit from **scripts/ha-bgp-anycast/** or `/etc/network/interfaces`). If the anycast address exists only on server-01, that’s why server-02 “has not responding at all”.

### 10.2 BGP on server-02 must be up and advertising the prefix

When server-01 is stopped, the **router** should only have a route to 192.168.200.100 via server-02. That requires server-02 to be running FRR and to advertise 192.168.200.100/32.

**On server-02:**

```bash
sudo systemctl status frr
sudo vtysh -c "show ip bgp summary"
sudo vtysh -c "show ip bgp 192.168.200.100/32"
```

- FRR must be running.
- BGP session to the router (e.g. 192.168.200.1) must be **Established**.
- The prefix **192.168.200.100/32** must be in the local BGP table and advertised (e.g. `show ip bgp` shows it as “s” or “*>”).

If BGP isn’t established on server-02, the router never learns 192.168.200.100 from server-02 and has no path after server-01 goes down.

### 10.3 Router must peer with **both** radius nodes

The upstream router (e.g. 192.168.200.1) must have **two** BGP neighbors: 192.168.200.21 (server-01) and 192.168.200.22 (server-02). If it only peers with server-01, when server-01 is down the router has no route to 192.168.200.100.

On the router, confirm both peers are configured and at least one is Established. When server-01 is stopped, the route to 192.168.200.100/32 should remain, via 192.168.200.22.

### 10.4 FreeRADIUS on server-02 must be running and listening

**On server-02:**

```bash
sudo systemctl status freeradius
ss -ulnp | grep -E '1812|1813'
```

FreeRADIUS should be active and listening on **0.0.0.0:1812** (and 1813 for accounting). If it listens only on a specific IP, ensure 192.168.200.100 is on `lo` (see 10.1). **clients.conf** on server-02 must include the **vip** client (192.168.200.100) with the same secret as on server-01.

### 10.5 Firewall on server-02

**On server-02:**

```bash
sudo iptables -L -n -v 2>/dev/null | head -40
# or
sudo nft list ruleset 2>/dev/null | head -60
```

Ensure UDP 1812 and 1813 are allowed from the clients/network (or from anywhere if your policy allows). If the firewall allows only server-01’s IP or a narrow range, traffic to 192.168.200.100 when routed via server-02 may be dropped.

### 10.6 Give BGP time to converge

After stopping FRR (or the whole server) on server-01, wait **1–2 minutes** for the BGP session to be declared down (hold timer) and for the router to remove the path. Then test with a **new** connection (e.g. new SSH, or radtest from another host to 192.168.200.100). Don’t reuse an existing TCP/UDP connection that was bound to server-01.

### 10.7 Quick checklist (when server-01 is stopped)

| Check | On server-02 | Command / Where |
|-------|--------------|------------------|
| Anycast IP on lo | 192.168.200.100/32 on lo | `ip addr show lo` |
| FRR running | bgpd up | `systemctl status frr` |
| BGP established | Neighbor to router Established | `vtysh -c "show ip bgp summary"` |
| Prefix advertised | 192.168.200.100/32 in BGP | `vtysh -c "show ip bgp"` |
| FreeRADIUS running | Listening 1812/1813 | `systemctl status freeradius`; `ss -ulnp \| grep 1812` |
| VIP in clients.conf | client vip 192.168.200.100 | Same as server-01 |
| Firewall | Allows 1812/1813 | iptables/nft |

On the **router**: both neighbors 192.168.200.21 and 192.168.200.22 configured; when server-01 is down, route to 192.168.200.100/32 via 192.168.200.22.

---

## 11. How to test anycast failover (real test)

Use a **client host** that reaches the VIP via your router (e.g. a workstation, or the pfSense box itself). Do **not** test from freeradius-node-a/freeradius-node-b to the VIP (same host can look like it works even when routing is wrong).

### 1. Both servers up – see which one answers

- On **freeradius-node-a**: `sudo tail -f /var/log/freeradius/radius.log`
- On **freeradius-node-b**: in another session, `sudo tail -f /var/log/freeradius/radius.log`
- From the **client** (different machine), run:
  ```bash
  radtest USER PASSWORD 192.168.200.100 0 YOUR_VIP_SECRET
  ```
  Replace USER, PASSWORD (a valid AD user/pass if you use PAP). For the secret: FreeRADIUS matches clients by **source IP** of the request. Use the **secret of the client that matches your test machine’s IP** (e.g. if you radtest from 192.168.200.50, use that client’s secret in clients.conf—add a `client` block for your test host if needed). The `vip` client (192.168.200.100) is the *destination*; it does not match the packet source. Use `0` as the NAS port.
- One of the two radius logs will show the request (e.g. `Auth: (N) Login OK` or `Access-Request`). Note which server it was (e.g. freeradius-node-a).

### 2. Stop freeradius-node-a

- On **freeradius-node-a**: `sudo systemctl stop freeradius`
- (Optional but clearer: also stop FRR so BGP withdraws the route: `sudo systemctl stop frr`)

### 3. Wait for BGP

- Wait **1–2 minutes** so the router (pfSense) sees the BGP session down and removes the path to 192.168.200.100 via freeradius-node-a.
- On **freeradius-node-b**: `sudo vtysh -c "show ip bgp summary"` – session to the router should still be **Established**.

### 4. Test again from the client

- From the **same client** (same machine as step 1), run again:
  ```bash
  radtest USER PASSWORD 192.168.200.100 0 YOUR_VIP_SECRET
  ```
- **Expected:** Request is **logged on freeradius-node-b** only. If you see it in freeradius-node-b’s log, failover works.
- **If it fails:** No reply or timeout → routing still points to freeradius-node-a (down), or firewall/secret wrong. Check router routes and freeradius-node-b’s FRR/FreeRADIUS/firewall.

### 5. Bring freeradius-node-a back

- On **freeradius-node-a**: `sudo systemctl start frr` (if you stopped it), then `sudo systemctl start freeradius`
- After 1–2 minutes, run `radtest` from the client again. Either server may get the request (equal cost); both should work.

### Quick checklist

| Step | What to do |
|------|------------|
| 1 | From a **client** (not freeradius-node-a/02), `radtest user pass 192.168.200.100 0 vip_secret`; watch freeradius-node-a and freeradius-node-b logs, see which one logs it. |
| 2 | On freeradius-node-a: `systemctl stop freeradius` (and optionally `systemctl stop frr`). |
| 3 | Wait 1–2 minutes. |
| 4 | From the **same client**, run `radtest` again. Request must appear in **freeradius-node-b** log only. |
| 5 | Start freeradius-node-a again; test again to confirm both can serve. |

If you don’t have `radtest` on the client, install the **freeradius-utils** package (Debian/Ubuntu) or equivalent, or use a real RADIUS client (e.g. VPN gateway, Wi‑Fi controller) and watch the radius logs while you connect.

### Failover still not working – find where it breaks

Run these in order when **freeradius-node-a is stopped** and the client gets no reply from 192.168.200.100.

**A. Router: does the route point to freeradius-node-b?**

- On **pfSense**: **Services → FRR → Routes** (or BGP Routes). Find **192.168.200.100/32**. When freeradius-node-a is down, the next-hop must be **192.168.200.22** (freeradius-node-b). If it still shows 192.168.200.21 or the route is gone, BGP is not failing over (check FRR on pfSense, both neighbors, hold timer).
- From the **client**, when freeradius-node-a is down: `ping 192.168.200.100` – does it reply? If yes, the route is correct and the problem is RADIUS or firewall. If no reply, routing is wrong.

**B. Does freeradius-node-b receive the packet?**

- On **freeradius-node-b** (with freeradius-node-a stopped), run: `sudo tcpdump -i any -n udp port 1812`
- From the **client**, run: `radtest USER PASS 192.168.200.100 0 CLIENT_SECRET`
- If **no packet** appears on freeradius-node-b: traffic to 192.168.200.100 is not reaching freeradius-node-b (routing or router still sending to freeradius-node-a). Fix BGP/routing first.
- If **packet appears** but no log in radius.log: FreeRADIUS is not accepting it (client config or firewall). Check **C** and **D**.

**C. Test freeradius-node-b directly (bypass anycast)**

- From the **same client**, run: `radtest USER PASS 192.168.200.22 0 CLIENT_SECRET` (use **192.168.200.22**, not the VIP, and the same client secret for your source IP).
- If this **works** (Access-Accept and freeradius-node-b logs it): freeradius-node-b and clients.conf are fine; the break is **routing to the VIP** when freeradius-node-a is down (router not using freeradius-node-b path).
- If this **fails**: the problem is on freeradius-node-b (FreeRADIUS, clients.conf for your client IP, or firewall on freeradius-node-b).

**D. clients.conf on freeradius-node-b**

- FreeRADIUS matches by **source IP**. Your radtest runs from the client’s IP (e.g. 192.168.200.50). There must be a **client** in clients.conf on freeradius-node-b whose **ipaddr** (or netmask) includes that IP, with the **secret** you use in radtest. Sync from freeradius-node-a must have copied clients.conf; if you added a client only on freeradius-node-a, sync again or add it on freeradius-node-b.

**E. Firewall on freeradius-node-b**

- Ensure UDP **1812** and **1813** are allowed from the client’s network (or from the router 192.168.200.1). Example: `sudo iptables -L -n -v` or `sudo nft list ruleset` and confirm no drop for 1812/1813.

**Summary**

| If… | Then… |
|-----|--------|
| Route on router still via 192.168.200.21 or no route when freeradius-node-a down | Fix BGP on pfSense (both peers, hold timer); wait longer after stopping freeradius-node-a. |
| ping 192.168.200.100 fails when freeradius-node-a down | Same as above – route not updated. |
| tcpdump on freeradius-node-b shows no packet when you radtest to VIP | Traffic not reaching freeradius-node-b; fix routing. |
| tcpdump shows packet but no radius log | Wrong client/secret or firewall on freeradius-node-b. |
| radtest to 192.168.200.22 works, to 192.168.200.100 fails when freeradius-node-a down | Routing to VIP is wrong; router not using freeradius-node-b path. |

---

## 12. VRRP vs BGP anycast

| | VRRP (current doc) | BGP anycast (this doc) |
|---|--------------------|-------------------------|
| **Address** | One VIP moves between nodes | Same IP on both; both advertise it |
| **Who serves** | Only current master | Whichever node routing chose (or both with ECMP) |
| **Dependency** | Same L2, VRRP | BGP and upstream router |
| **Use when** | Simple active/standby, no BGP in network | You have BGP and want anycast/active-active |

You can run **either** VRRP **or** BGP anycast for 192.168.200.100, not both at once on the same address.
