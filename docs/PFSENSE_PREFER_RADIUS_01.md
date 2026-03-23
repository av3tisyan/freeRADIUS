# pfSense: Prefer freeradius-node-a for the anycast VIP

When both freeradius-node-a and freeradius-node-b advertise 192.168.200.100/32 via BGP, pfSense can load-balance and send traffic to either. To make **freeradius-node-a** the preferred server (traffic only goes to freeradius-node-b when freeradius-node-a is down), set a **higher local-preference** for the path from freeradius-node-a on pfSense.

**Prerequisites:** FRR package installed on pfSense, BGP enabled, both neighbors 192.168.200.21 and 192.168.200.22 configured and Established.

---

## Steps on pfSense

### 1. Prefix list (optional but recommended)

- Go to **Services → FRR** (or **Services → FRR → Prefix Lists** / **Global** depending on your version).
- Add a **Prefix List**:
  - **Name:** `radius-anycast`
  - **Sequence:** `10`
  - **Action:** Permit
  - **Network:** `192.168.200.100/32`
- Save.

### 2. Route map – set local-preference 200

- Go to **Services → FRR → Route Maps**.
- Add a **Route Map**:
  - **Name:** `prefer-freeradius-node-a`
  - **Sequence:** `10`
  - **Action:** Permit
  - **Set Local Preference:** `200` (or “Set” and value `200`)
  - **Match Prefix List:** `radius-anycast` (if you created it; otherwise leave empty to affect all routes from the neighbor)
- Save.

### 3. Apply route map only to freeradius-node-a

- Go to **Services → FRR → BGP → Neighbors**.
- **Edit** the neighbor **192.168.200.21** (freeradius-node-a).
- Under **Peer Filtering** (or **Inbound / Outbound**):
  - Set **Inbound Route Map** to **prefer-freeradius-node-a**.
- Save.
- **Edit** the neighbor **192.168.200.22** (freeradius-node-b):
  - Leave **Inbound Route Map** empty (or default). Do **not** set prefer-freeradius-node-a here.
- Save.

### 4. Apply and restart FRR

- Click **Apply** or **Save** in the FRR section.
- Restart FRR if the UI prompts you (or **Services → FRR → Restart FRR**).

---

## Result

- Routes to **192.168.200.100/32** from **192.168.200.21** get **local-preference 200**.
- Routes from **192.168.200.22** keep default **local-preference 100**.
- pfSense prefers the path with higher local-pref, so **all traffic to 192.168.200.100 goes to freeradius-node-a** when it’s up.
- When freeradius-node-a (or its BGP session) is down, that path is withdrawn and **traffic goes to freeradius-node-b**.

---

## Verify

- **Services → FRR → Routes** (or BGP Routes): the route to **192.168.200.100/32** should show next-hop **192.168.200.21** when both radius nodes are up.
- From a client, `ping 192.168.200.100` or use RADIUS; then on freeradius-node-a run `sudo tail -f /var/log/freeradius/radius.log` and confirm requests appear there. Stop FreeRADIUS or FRR on freeradius-node-a; after BGP converges, the same test should hit freeradius-node-b.

See also [HA_BGP_ANYCAST_SETUP.md](HA_BGP_ANYCAST_SETUP.md) §4.2.

---

## If it doesn’t work (pfSense route map)

1. **Route map with no match** – Create a route map that does **not** use “Match Prefix List”. Set only **Local Preference 200** and apply it **inbound** to neighbor **192.168.200.21**. That way every route received from freeradius-node-a gets 200; the prefix list might not be matching on your FRR version.
2. **Inbound, not outbound** – The route map must be applied **inbound** (routes *from* 192.168.200.21). If the GUI has “Import” / “In”, use that. Do not use outbound for this.
3. **Restart FRR** – After changing route maps or neighbors, **Services → FRR** and use “Restart FRR” or “Apply” so the new config is loaded.
4. **Check Routes** – In **Services → FRR → Routes** (or BGP Routes), see which next-hop is used for **192.168.200.100/32**. If it still shows 192.168.200.22 or both, the route map is not applied or not taking effect.

**Easier option:** Use **MED on the radius servers** (below) so pfSense prefers freeradius-node-a without relying on pfSense route maps.

---

## Alternative: Prefer freeradius-node-a using MED (on the radius servers)

If the pfSense route map doesn’t work, set **lower MED** on **freeradius-node-a** only. pfSense will prefer the path with lower MED. No route maps needed on pfSense.

### On freeradius-node-a only

Edit `/etc/frr/frr.conf`. In the BGP section, add a route-map that sets MED on outbound updates, and apply it to the neighbor:

```text
router bgp 65004
 bgp router-id 192.168.200.21
 no bgp ebgp-requires-policy
 neighbor 192.168.200.1 remote-as 65000
 neighbor 192.168.200.1 route-map SET_MED_OUT out
 !
 address-family ipv4 unicast
  network 192.168.200.100/32
 exit-address-family
exit
!
route-map SET_MED_OUT permit 10
 set metric 50
!
```

Then:

```bash
sudo systemctl restart frr
```

### On freeradius-node-b

Do **not** add any route-map or MED. Leave the config as-is (or set a higher MED like 100 if you want to be explicit). Default MED is often 0; 50 from freeradius-node-a can still be preferred depending on the router. To be sure freeradius-node-b is worse, you can add on freeradius-node-b:

```text
route-map SET_MED_OUT permit 10
 set metric 100
!
```

and `neighbor 192.168.200.1 route-map SET_MED_OUT out`, so freeradius-node-a sends MED 50 and freeradius-node-b sends MED 100 → pfSense prefers 50 (freeradius-node-a).

### Result

- freeradius-node-a advertises 192.168.200.100/32 with **MED 50**.
- freeradius-node-b advertises 192.168.200.100/32 with **MED 100** (or default).
- pfSense prefers the path with **lower MED** → traffic to 192.168.200.100 goes to **freeradius-node-a** when both are up. When freeradius-node-a is down, only the path via freeradius-node-b remains.
