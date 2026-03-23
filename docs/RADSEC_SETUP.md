# RadSec (RADIUS over TLS) setup

RadSec runs RADIUS over **TCP port 2083** with **TLS** encryption, so traffic between the NAS and FreeRADIUS is encrypted. Authentication logic is unchanged (same default virtual server, LDAP, OU policy).

## What was added

| Item | Purpose |
|------|--------|
| [etc/freeradius/3.0/sites-available/radsec](../etc/freeradius/3.0/sites-available/radsec) | RadSec listen (port 2083) and `clients radsec` |
| [etc/freeradius/3.0/sites-enabled/radsec](../etc/freeradius/3.0/sites-enabled/radsec) | Enabled copy (loaded with `$INCLUDE sites-enabled/`) |

- **Listen:** `*:2083` TCP, TLS with same certs as EAP (`server.key`, `server.pem`, `ca.pem`). Requests go to **virtual_server = default** (same as UDP 1812).
- **Clients:** Same IPs as in `clients.conf` (localhost, VPN gateway, Wi‑Fi NAS subnet, wired NAS). Replace `REPLACE_RADSEC_SECRET` / Wi‑Fi / wired RadSec secrets and the example IPs with your values. Only connections from listed client IPs are accepted on 2083.
- **Client certs:** `require_client_cert = no` so NAS can connect with TLS without a client certificate (identified by IP). Set to `yes` and issue client certs for mutual TLS if your NAS support it.

## Deploy

1. Copy `etc/freeradius/3.0/` to `/etc/freeradius/3.0/` on both nodes (including `sites-enabled/radsec`).
2. Ensure EAP certs exist and `server.key` is decrypted (same as for EAP).
3. Restart FreeRADIUS: `sudo systemctl restart freeradius`.
4. Open **TCP 2083** on the firewall for the RADIUS VIP (and/or node IPs) from your NAS subnets.

## NAS support

Many NAS (including common firewalls and Wi‑Fi controllers) do **not** speak RadSec natively; they use UDP 1812/1813. Options:

1. **Use UDP for now** – Keep pointing NAS at the VIP on port 1812; RadSec is then ready for future RadSec-capable clients or a proxy.
2. **RadSec proxy** – Run **radsecproxy** (or similar) on a host that the NAS can reach; the proxy accepts UDP 1812 from the NAS and forwards over RadSec (TCP 2083) to FreeRADIUS. That way the NAS config stays UDP while the leg to FreeRADIUS is encrypted.
3. **If your NAS supports RadSec** – Point it at **your RADIUS VIP:2083** (TCP), use the secret you set in `clients radsec`, and ensure the NAS trusts the CA that signed the FreeRADIUS server cert.

## Import CA into pfSense

So pfSense can trust the FreeRADIUS server certificate (for RADIUS or RadSec over TLS), import your **RADIUS CA** (the one that signed `server.pem`) into pfSense:

1. **Get the CA file**  
   On the radius server the CA is at `/etc/freeradius/3.0/certs/ca.pem`. Copy its contents (PEM format, `-----BEGIN CERTIFICATE-----` … `-----END CERTIFICATE-----`).

2. **In pfSense:** **System → Certificates**, open the **CAs** tab, click **Add**.

3. **Method:** Choose **Import an Existing Certificate Authority**.

4. **Descriptive name:** e.g. `YourOrg RADIUS CA`.

5. **Certificate data:** Paste the full PEM (including the BEGIN/END lines). Leave **Certificate Private Key** empty (you are importing the CA only, not a server cert with key).

6. **Save.**  
   The CA is now in pfSense’s trust store. When you add or edit a RADIUS client (e.g. **System → User Manager → RADIUS**) or any service that connects to FreeRADIUS over TLS, select this CA so pfSense verifies the server certificate instead of failing with “self-signed certificate”.

## Test

From a host that can reach the RADIUS server:

```bash
# Check that 2083 is listening (after restart)
sudo ss -tlnp | grep 2083
```

**Testing from your laptop:** Port 2083 only accepts connections from IPs listed in `clients radsec`. If you run `openssl s_client -connect <radius-ip>:2083` from a host whose IP is not in that list, the server closes the connection (no cert, errno 54/104). To verify TLS:

- **Option A (recommended):** SSH to the radius server and test locally (localhost is a radsec client):
  ```bash
  ssh freeradius-node-a
  openssl s_client -connect localhost:2083 -tls1_2 -showcerts
  ```
- **Option B:** On the server, add your laptop’s IP as a radsec client (temporary, for testing only), restart FreeRADIUS, then run `openssl s_client` from the laptop.

With a RadSec-capable client (e.g. radsecproxy or `radtest` over a TLS tunnel), send a test request to the VIP on port 2083.

**Debugging RadSec:** TLS sockets need threading. Do **not** use `radiusd -X` (it runs single-threaded and RadSec will not work). Use (on Debian/Ubuntu the binary is often `freeradius`):
```bash
sudo freeradius -fxx -l stdout
```
Look for "Listening on auth+acct proto tcp address * port 2083 (TLS)".

## Troubleshooting: "no peer certificate" / handshake reads 0 bytes

If `openssl s_client -connect <server>:2083 -tls1_2 -showcerts` shows **"no peer certificate available"**, **"SSL handshake has read 0 bytes"**, and **write:errno=104** (connection reset by peer), the server accepted TCP but then closed the connection without sending TLS data. The server logs are the only way to see why.

**Quick check (run on freeradius-node-a):**

1. Stop the service and run debug with threading (so RadSec actually runs). On Debian/Ubuntu use `freeradius`:
   ```bash
   sudo systemctl stop freeradius
   sudo freeradius -fxx -l stdout
   ```
2. In the first ~80 lines, find the line for port 2083. It **must** say **(TLS)**:
   - `Listening on auth+acct proto tcp address * port 2083 (TLS) bound to server default` → TLS loaded; continue to step 3.
   - Line for 2083 **without** `(TLS)` → TLS did not load. Look for errors above about certificate, key, or file; fix paths (use `${confdir}/certs/...`) or key password.
   - No line for 2083 at all → RadSec site not loaded; check `sites-enabled/radsec` and that no syntax error prevents the include.
3. Leave that terminal running. In another terminal (or from your laptop):  
   `openssl s_client -connect localhost:2083 -tls1_2 -showcerts`  
   Watch the **first** terminal at the moment the connection is made. Any new line (error, TLS, or connection message) is the cause of the reset.

**On the RadSec server (detailed):**

1. **Threading required**  
   RadSec needs threading. If you see "Threading must be enabled for TLS sockets to function properly", you are running single-threaded (e.g. `radiusd -X` or `freeradius -X`). Use `freeradius -fxx -l stdout` for debug instead; the service (`systemctl start freeradius`) uses threading by default.

2. **Confirm TLS is active on 2083**  
   Run in debug (with threading) and check the listen line:
   ```bash
   sudo freeradius -fxx -l stdout 2>&1 | head -120
   ```
   You must see something like:
   ```text
   Listening on auth+acct proto tcp address * port 2083 (TLS) bound to server default
   ```
   If the line for 2083 does **not** contain **(TLS)**, the listen block did not get a valid TLS config (e.g. cert load failed). Check the same output for any **TLS**, **certificate**, or **key** error messages.

3. **Verify certificate paths**  
   `${certdir}` and `${cadir}` are set in `radiusd.conf` (often `confdir = /etc/freeradius/3.0`, so `certdir`/`cadir` = `/etc/freeradius/3.0/certs`). Ensure these files exist and are readable by the `freerad` user:
   ```bash
   sudo ls -la /etc/freeradius/3.0/certs/server.key /etc/freeradius/3.0/certs/server.pem /etc/freeradius/3.0/certs/ca.pem
   ```
   If your install uses a different `confdir`, adjust the path. The RadSec `tls` block uses `${confdir}/certs/server.key`, `${confdir}/certs/server.pem`, and `${confdir}/certs/ca.pem`.

4. **Key password**  
   If `server.key` is encrypted, set `private_key_password = <password>` in the RadSec `tls { }` block (same as for EAP). Wrong or missing password can prevent the TLS context from being created.

5. **Watch server logs while testing**  
   With `freeradius -fxx -l stdout` running, connect from another host:
   ```bash
   openssl s_client -connect 192.168.200.21:2083 -tls1_2 -showcerts
   ```
   Any TLS or connection error in the **radiusd** output when the connection hits indicates why the handshake failed.

6. **Optional: use the stock TLS site**  
   To rule out config differences, you can enable the distribution’s `tls` virtual server (`sites-available/tls`) instead of the custom radsec site: symlink it in `sites-enabled`, then edit its `tls { }` block to use your EAP cert paths (`server.key`, `server.pem`, `ca.pem`) and add your clients under `clients radsec { }`. If the handshake works with the stock site, the issue is in the custom radsec site or how it’s included.

## Security

- RadSec uses the same TLS 1.2 and strong ciphers as your EAP config.
- Restrict firewall so only NAS (and any RadSec proxy) can reach 192.168.200.100:2083.
- To harden further, set `require_client_cert = yes` in the RadSec `tls` block and issue client certificates to each NAS (or proxy) that connects.
