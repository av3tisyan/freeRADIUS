# Wired 802.1X: "Authentication server is not responding"

Wi‑Fi works but the wired switch/NAS reports that the RADIUS server is not responding. Check the following.

---

## 1. Switch must be a RADIUS client

The server **only responds** to requests from IPs defined in **`clients.conf`**. If the switch IP is missing or wrong, the server drops or ignores the packet and the switch sees "no response".

- **On the server**, open `/etc/freeradius/3.0/clients.conf`.
- Ensure there is a **client** whose **ipaddr** is the **switch’s management IP** (the one the switch uses as source for RADIUS; e.g. 192.168.202.20 for wired-nas-01).
- The **secret** must match exactly what is configured on the switch (RADIUS shared secret). If it doesn’t, the server may drop the request (invalid Message-Authenticator) and not send a reply.

Example (ipaddr and secret must match the switch):

```text
client wired-nas-01 {
    ipaddr = 192.168.202.20
    proto = *
    require_message_authenticator = yes
    secret = "same-secret-as-on-the-switch"
    shortname = wired-nas-01
}
```

Restart FreeRADIUS after changing: `sudo systemctl restart freeradius`.

---

## 2. Switch RADIUS server configuration

On the switch, confirm:

- **RADIUS server IP** is the RADIUS server the switch can reach (e.g. your VIP 192.168.200.100 or the node IP 192.168.200.21).
- **Port** is **1812** (auth).
- **Shared secret** is exactly the same as in `clients.conf` for this client (no extra spaces, same case).

---

## 3. Network and firewall

- The switch must be able to reach the RADIUS server IP (routing, no ACL blocking the switch subnet).
- On the **RADIUS server** (and any firewall in between), allow **UDP 1812** **from** the switch IP (e.g. 192.168.202.20) **to** the RADIUS server IP.

Examples:

```bash
# On the server, check that something is listening on 1812
sudo ss -ulnp | grep 1812
```

If using firewalld:

```bash
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.202.20" port port="1812" protocol="udp" accept'
```

---

## 4. Verify on the server

- FreeRADIUS must be running: `sudo systemctl status freeradius`.
- It must listen on the address the switch uses: e.g. `sudo ss -ulnp | grep 1812` should show radius/freeradius bound to the right IP (often `*` or the VIP).

If you see requests in the logs from the switch but still get "not responding", the usual cause is **wrong or missing client secret** (server drops due to Message-Authenticator). Fix the secret in `clients.conf` and on the switch so they match, then restart FreeRADIUS.

---

## 5. Switch CLI sanity check (example: Ubiquiti EdgeSwitch)

From privileged mode, useful commands (names vary by vendor/firmware):

| Check | Example CLI |
|-------|----------------|
| 802.1X status | `show dot1x` |
| AAA | `show aaa` / `show running-config \| include aaa` |
| RADIUS servers | `show radius` / `show running-config \| include radius` |
| Per-port | `show dot1x interface 0/4` (use your interface) |

Enable **VLAN assignment** for dynamic VLAN in the GUI if the CLI has no equivalent. For tagged-only ports and blocking unauthenticated access, see **§6** in [GROUP_VLAN_ASSIGNMENT.md](GROUP_VLAN_ASSIGNMENT.md).
