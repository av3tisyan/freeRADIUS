# Group-based VLAN assignment (wired 802.1X NAS)

Example AD group names used in this repo: **RADIUS-Corp** (VLAN 300), **RADIUS-SiteA** (100), **RADIUS-SiteB** (200), **RADIUS-Guest** (90), default VLAN **1000**. Replace with your real **cn** values and VLAN IDs.

For wired clients, RADIUS should send **Tunnel-Type** and **Tunnel-Private-Group-Id** based on the user's AD group. This requires:

- **LDAP** populates **LDAP-Group** (group `name_attribute = cn`, `membership_attribute = member`, `edir = no`).
- **VLAN in reply** can be set in either:
  - **inner-tunnel post-auth** – set Tunnel-Type / Tunnel-Private-Group-Id directly in the inner server (EAP merges reply to outer). Used when all 802.1X (WiFi + wired) use inner-tunnel and you want one place for group→VLAN.
  - **default post-auth** – inner-tunnel copies LDAP-Group to **outer.session-state**; default post-auth runs only for wired NAS clients (e.g. `Client-Shortname =~ /^wired-nas/`) and sets VLAN from session-state. Keeps wired-only logic in default.

---

## Quick fix when a user gets default VLAN 1000 instead of 300 (LDAP-Group empty)

If group assignment still doesn't work (e.g. user gets VLAN 1000 instead of 300), **LDAP-Group is empty**. Do this **on the primary RADIUS node**:

1. **Widen group base_dn**  
   Edit `/etc/freeradius/3.0/mods-enabled/ldap`. In the **group { }** block set:
   ```text
   base_dn = "DC=example,DC=com"
   ```
   (Replace with your domain; not a single OU if your VLAN groups live elsewhere.)

2. **Ensure group block has:**  
   `name_attribute = "cn"`, `membership_attribute = "member"`, and at top level `edir = no`.

3. **Restart:**  
   `sudo systemctl restart freeradius`

4. **Confirm in AD** that the user is **member of** a group whose **name (cn)** matches your post-auth logic (e.g. `RADIUS-Corp`). That group must live under your group `base_dn` (or a child OU).

5. **Verify:** Run `sudo freeradius -X`, authenticate once from the wired switch/NAS. In the trace look for:
   - inner-tunnel post-auth: `if (&LDAP-Group)  -> TRUE` and the group name.
   - default post-auth: `Tunnel-Private-Group-Id := "300"` (or the VLAN you expect).

If LDAP-Group is still FALSE, the user is not in any group under that base_dn, or the group's `member` attribute doesn't contain the user's DN. Check in AD (e.g. user → Member of; group → Members).

---

## 1. LDAP module (`mods-enabled/ldap`)

In the **group** section you must have:

- **name_attribute = "cn"** – so the group’s Common Name (e.g. `RADIUS-Corp`) is added to **LDAP-Group**.
- **membership_attribute = "member"** – for AD, the group object stores members in `member`.
- **edir = no** at the top level – for AD bind auth.

With these, after inner-tunnel authorize + authenticate, **LDAP-Group** will contain the user’s group name(s).

---

## 2. Where to set VLAN: inner-tunnel vs default

### Option A: VLAN in inner-tunnel post-auth (one place for all 802.1X)

Set Tunnel-Type / Tunnel-Private-Group-Id in **inner-tunnel** `post-auth`. The inner reply is merged into the outer reply by EAP, so the switch receives the VLAN. Use **Tunnel-Type := 13** (VLAN) and **Tunnel-Medium-Type := 6** (IEEE-802). Example:

```text
# inner-tunnel post-auth
if (LDAP-Group == "RADIUS-Corp") {
    update reply { &Tunnel-Type := 13; &Tunnel-Medium-Type := 6; &Tunnel-Private-Group-Id := "300" }
}
elsif (LDAP-Group == "RADIUS-SiteA") { ... }
else { update reply { &Tunnel-Type := 13; &Tunnel-Medium-Type := 6; &Tunnel-Private-Group-Id := "1000" } }
```

If the user is in **multiple groups**, `LDAP-Group` may be a list and `== "RADIUS-Corp"` might not match. Use regex instead: `if (&LDAP-Group =~ /^RADIUS-Corp$/)` or `=~ /(^|,)RADIUS-Corp(,|$)/` so one of the groups matches.

### Option B: VLAN in default post-auth (wired NAS only, from session-state)

Inner-tunnel copies LDAP-Group to outer: `if (&LDAP-Group) { update outer.session-state { &LDAP-Group := &LDAP-Group } }`. The **default** site post-auth runs only for wired NAS clients (matching your `Client-Shortname` pattern) and sets VLAN from **session-state:LDAP-Group**.

Example (add or merge into the existing `post-auth { }` in **default**):

```text
post-auth {
    # ... existing post-auth (e.g. update reply, exec, etc.) ...

    # Wired 802.1X (e.g. shortname wired-nas-01): group-based VLAN. Only when we have a shortname.
    if (&request:Client-Shortname =~ /^wired-nas/) {
        if (&session-state:LDAP-Group) {
            if (&session-state:LDAP-Group =~ /^RADIUS-Corp$/) {
                update reply {
                    &Tunnel-Type := VLAN
                    &Tunnel-Medium-Type := IEEE-802
                    &Tunnel-Private-Group-Id := "300"
                }
            }
            else if (&session-state:LDAP-Group =~ /^RADIUS-SiteB$/) {
                update reply {
                    &Tunnel-Type := VLAN
                    &Tunnel-Medium-Type := IEEE-802
                    &Tunnel-Private-Group-Id := "200"
                }
            }
            # Add more groups as needed
            else {
                update reply {
                    &Tunnel-Type := VLAN
                    &Tunnel-Medium-Type := IEEE-802
                    &Tunnel-Private-Group-Id := "1000"
                }
            }
        }
        else {
            # No LDAP-Group (e.g. user not in any group): default VLAN
            update reply {
                &Tunnel-Type := VLAN
                &Tunnel-Medium-Type := IEEE-802
                &Tunnel-Private-Group-Id := "1000"
            }
        }
    }

    # ... rest of post-auth ...
}
```

Adjust group names and VLAN IDs to match your AD groups and switch VLANs (e.g. RADIUS-Corp → 300, RADIUS-SiteB → 200, default → 1000). The **if (&session-state:LDAP-Group)** guard avoids errors when LDAP-Group is missing.

---

## 3. Verify on the server

1. **LDAP:** Ensure `mods-enabled/ldap` has the group `name_attribute`, `membership_attribute`, and `edir = no` as above. Restart FreeRADIUS.

2. **Default post-auth:** Ensure the **default** virtual server’s `post-auth` contains the wired-NAS VLAN block (or equivalent). Restart FreeRADIUS.

3. **Debug:** Run `sudo freeradius -X`, authenticate from the wired NAS with a user in an AD group (e.g. RADIUS-Corp). In the trace, check:
   - inner-tunnel authorize: **LDAP-Group** is set after ldap.
   - If using **Option A** (VLAN in inner-tunnel): inner-tunnel post-auth adds Tunnel-Type / Tunnel-Private-Group-Id to the reply.
   - If using **Option B** (VLAN in default): inner-tunnel post-auth copies LDAP-Group to outer.session-state; default post-auth adds **Tunnel-Private-Group-Id** from session-state:LDAP-Group.

4. **Switch:** VLAN Assignment Mode must be **Enabled** (Port Access Control → Configuration). Port must be in the RADIUS-assigned VLANs (e.g. 300, 1000) as **Tagged**.

---

## 4. Common reasons it doesn’t work

| Symptom | Cause | Fix |
|--------|--------|-----|
| LDAP-Group empty in debug (`if (&LDAP-Group) -> FALSE` in inner-tunnel post-auth) | Group search returns no groups: **group `base_dn`** is too narrow and the user's group lives in another OU. | Set group `base_dn` to a DN that **includes** where your VLAN groups live (e.g. `DC=example,DC=com`). Ensure `name_attribute = "cn"` and `membership_attribute = "member"`. |
| session-state:LDAP-Group empty in default | inner-tunnel not copying to outer (Option B only) | inner-tunnel post-auth must have `if (&LDAP-Group) { update outer.session-state { &LDAP-Group := &LDAP-Group } }`. |
| Wrong or no VLAN in reply | Wrong group check or no VLAN block | If Option A: fix inner-tunnel post-auth (use `=~` if user in multiple groups). If Option B: add wired-NAS VLAN block in default post-auth; use `=~ /^RADIUS-Corp$/` etc. (FreeRADIUS may not support `(?i)`). |
| User in multiple groups | LDAP-Group may list multiple; regex matches first | Use regex that matches the desired group, or use a dedicated RADIUS VLAN group in AD. |

**Config in this repo:** `sites-available/default`, `inner-tunnel`, `radsec` (symlinked from `sites-enabled/`). `clients.conf` holds NAS placeholders.

---

## 5. Other segmentation options (besides group → VLAN)

- **Reject if not in allowed groups** – In inner-tunnel `authorize`, after `-ldap`: `if (!&LDAP-Group) { reject }` or regex on `LDAP-Group` to allow only `RADIUS-Corp|RADIUS-SiteA|…`.
- **Filter-Id / vendor ACL** – In post-auth, set **Filter-Id** (or a VSA); switch must apply ACL from that value.
- **Class / custom VSAs** – Map group → **Class** if your NAS uses it for policy.
- **L3 firewall** – Keep group→VLAN in RADIUS; restrict traffic per VLAN on the router/firewall.
- **Dedicated AD groups** – One RADIUS VLAN group per user simplifies matching when users have many `memberOf` entries.

---

## 6. Tagged VLANs / no guest access (switch-side)

- **No usable network until auth:** Leave guest/unauthenticated VLAN empty or use an isolated VLAN without DHCP/routes; port control **Auto**.
- **Tagged RADIUS VLANs on the port:** In the switch VLAN UI, mark RADIUS-assigned VLANs **Tagged** on the 802.1X port; the client must support 802.1Q. If not, use **Untagged** for a single access VLAN.
- RADIUS still returns Tunnel-Type / Tunnel-Private-Group-Id; the switch chooses tagged vs untagged on the wire.
