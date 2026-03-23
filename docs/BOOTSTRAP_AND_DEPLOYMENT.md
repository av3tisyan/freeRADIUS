# FreeRADIUS HA Cluster – Bootstrap and Deployment

**Before you start:** Replace all placeholders in `etc/freeradius/3.0/` (see main [README](../README.md#placeholders-to-replace)): client secrets, LDAP server/DN/password, TLS key password, RadSec secret, and example IPs. Edit cert `.cnf` files for your domain.

## 1. BlastRADIUS (CVE-2024-3596) Mitigation

- **clients.conf**: Every client has `require_message_authenticator = yes`. Do not disable this.
- Ensure all NAS (VPN gateway, Wi‑Fi, wired) send **Message-Authenticator** in Access-Request. Upgrade NAS firmware if needed.
- Optional in `radiusd.conf` (security subsection): `require_message_authenticator = auto` or `true`, and `limit_proxy_state = auto` for global hardening.

## 2. Certificate and TLS Bootstrap

### 2.0 Fix Makefile before first make/bootstrap

On the server, the stock Makefile’s `grep default_days ca.cnf` matches both `default_days` and `default_crl_days`, which breaks the openssl `-days` argument. Run once:

```bash
sudo bash /etc/freeradius/3.0/certs/fix-makefile-default_days.sh
```

Then use bootstrap or make as below.

### 2.1 Regenerate all certs (clean slate)

To remove all certificates and generate new CA + server cert with subjectAltName:

```bash
sudo bash /etc/freeradius/3.0/certs/regenerate-certs.sh
```

Optional args: `regenerate-certs.sh [ /path/to/certs [ freerad_user ] ]`. Default certs path is `/etc/freeradius/3.0/certs`, default user/group is `freerad`. Then restart FreeRADIUS.

### 2.2 Generate server key and certificate (with subjectAltName)

```bash
cd /etc/freeradius/3.0/certs
# Use server.cnf from this repo (edit commonName and subjectAltName in xpextensions for your domain).
sudo cp /path/to/this/repo/etc/freeradius/3.0/certs/server.cnf .

# Create key with passphrase (recommended at creation).
sudo openssl genrsa -aes256 -out server.key 2048

# Generate self-signed cert (subjectAltName in server.cnf).
sudo openssl req -new -x509 -key server.key -out server.pem -days 3650 -config server.cnf
# Enter passphrase when prompted.
```

### 2.3 Remove passphrase so systemd can start without manual input

```bash
cd /etc/freeradius/3.0/certs
# Decrypt key: writes new key without passphrase.
sudo openssl rsa -in server.key -out server.key.decrypted
sudo mv server.key server.key.encrypted
sudo mv server.key.decrypted server.key
```

### 2.4 Permissions (required for FreeRADIUS)

```bash
cd /etc/freeradius/3.0/certs
sudo chown freerad:freerad server.key server.pem
sudo chmod 640 server.key
sudo chmod 644 server.pem
```

- All `.key` files must be **640** and owned by **freerad** (or the user that runs `radiusd`).

### 2.5 CA for EAP (if using your own CA)

Place your CA cert in `certs/ca.pem` and set in `eap` → `tls-config tls-common` → `ca_file = ${cadir}/ca.pem`. Ensure `cadir` points to the same directory.

## 3. HA Synchronization (rsync)

Sync `/etc/freeradius/3.0/` from Node 1 to Node 2 so both nodes run the same config. Full guide: **docs/RSYNC_HA_SYNC.md**.

**From Node 1** (replace user and Node 2 IP; use `--rsync-path="sudo rsync"` so the remote side can write to `/etc`):

```bash
sudo rsync -avz --delete --rsync-path="sudo rsync" /etc/freeradius/3.0/ user@NODE2_IP:/etc/freeradius/3.0/
```

Example:

```bash
sudo rsync -avz --delete --rsync-path="sudo rsync" /etc/freeradius/3.0/ deploy-user@192.168.200.22:/etc/freeradius/3.0/
```

Sync **certs** only if both nodes share the same certs; otherwise exclude `*.key`/`*.pem` (see RSYNC_HA_SYNC.md) or generate certs per node. After sync, set ownership and restart FreeRADIUS on Node 2.

## 4. LDAP (AD) Password

Set the bind account password in `mods-enabled/ldap`: replace `REPLACE_LDAP_BIND_PASSWORD_ON_SERVER` with the actual password on the server (do not commit it). Options:

- **In config:** Edit `password = "..."` in `mods-enabled/ldap` on the server only.
- **Option A (env):** `export RADIUS_LDAP_PASSWORD='yourpassword'` before starting `radiusd`, or in systemd: `Environment=RADIUS_LDAP_PASSWORD=yourpassword` (if your config references it).
- **Option B (file):** Create a restricted file, e.g. `/etc/freeradius/3.0/ldap-password`, and in the `ldap` module set `password = /path/to/ldap-password` if your FreeRADIUS version supports it.

## 5. Firewall / VPN policy integration (e.g. pfSense)

- **NAS-Port-Type = Virtual**: Sent by many VPN gateways for VPN endpoints. In the **default** site `post-auth`, branch on this to apply VPN-specific reply attributes.
- **AD groups → firewall alias (Class):**  
  Set the RADIUS **Class** attribute from AD group membership so your firewall can map users to aliases (e.g. VPN group).

**Example (add to default site `post-auth`):**

```text
# Optional: VPN – NAS-Port-Type = Virtual
if (NAS-Port-Type == Virtual) {
    # Add Class for pfSense alias mapping (e.g. VPN_Users).
    # Adjust to your LDAP group attribute; memberOf may need parsing.
    update reply {
        &Class := "VPN_Users"
    }
}

# Optional: set Class from AD group for all successful logins
# (requires LDAP group in request from inner-tunnel or default authorize)
# update reply {
#     &Class := "%{LDAP-Group}"
# }
```

On your firewall (e.g. pfSense), configure the RADIUS client and use the **Class** attribute to assign the user to a firewall alias or VPN group.

Ensure your VPN gateway (and any other NAS) send **Message-Authenticator** and use the shared secret defined in **clients.conf**.

## 6. Run bootstrap (high level)

1. Install FreeRADIUS 3.2 on Debian 12 (e.g. `apt install freeradius`).
2. Copy this repo’s `etc/freeradius/3.0/` to `/etc/freeradius/3.0/` and **replace all placeholders** (clients.conf, ldap, eap, radsec, cert .cnf files).
3. Generate server cert (edit server.cnf/xpextensions for your domain), then decrypt `server.key` if needed and set permissions (steps 2.1–2.4).
4. Set LDAP bind password and all client/RadSec secrets on the server.
5. Test: `radiusd -XC` then `radtest ...` against inner-tunnel (port 18120) and default (1812).
6. Enable and start: `systemctl enable freeradius && systemctl start freeradius`.
7. Configure rsync (or your method) for HA between Node 1 and Node 2.

## 7. EAP-TTLS WiFi – what to install on client endpoints

For **EAP-TTLS** WiFi, clients do **not** use a client certificate. They only need to **trust the CA** that signed the FreeRADIUS server certificate so the TLS tunnel can be established. Inner auth is username/password (PAP) against AD.

### Certificate to distribute to endpoints

| What | File on server | Use on client |
|------|----------------|---------------|
| **CA certificate** | `/etc/freeradius/3.0/certs/ca.pem` | Import as “Root CA” / “Server CA” in the WiFi (802.1X) profile |

- **Do not** distribute the server cert (`server.crt` / `server.pem`) unless you want to pin the exact server (rare).
- **Do not** distribute `client.pem` / `client.p12` for EAP-TTLS; those are for EAP-TLS (client cert auth). For TTLS you use username/password inside the tunnel.

### Getting ca.pem onto clients

1. **Copy from RADIUS server** (replace `freeradius-node-a` with your hostname):
   ```bash
   scp root@freeradius-node-a:/etc/freeradius/3.0/certs/ca.pem ./YourOrg-RADIUS-CA.pem
   ```
2. Distribute **YourOrg-RADIUS-CA.pem** (or the same file renamed) via:
   - Manual install on each device, or
   - MDM (Intune, Jamf, etc.) as a “trusted root” or “WiFi payload CA”, or
   - GPO (Windows): deploy to “Trusted Root Certification Authorities” and reference in the 802.1X wired/wireless profile.

### WiFi (802.1X) profile settings on endpoints

- **EAP method:** EAP-TTLS (or “TTLS”).
- **Phase 2 / Inner:** PAP (or “PAP” / “Password”).
- **Outer identity:** `anonymous` (for privacy; matches your FreeRADIUS setup).
- **CA certificate / Root CA / Server CA:** select the imported **ca.pem** (your RADIUS CA).  
  This tells the device to trust the server cert presented by FreeRADIUS (which is signed by this CA).
- **Username / Password:** either prompt each time or store in the profile (less secure). These are the AD (sAMAccountName) credentials.

### Platform notes

- **Windows (Wired/Wireless 802.1X):** Use “Verify the server’s identity” and select the CA cert; EAP type TTLS, inner PAP, anonymous outer identity.
- **macOS / iOS:** WiFi profile: EAP-TTLS, Phase 2 = PAP, “Trust” = your CA cert (installed in Profiles or Keychain).
- **Android:** WiFi → EAP method TTLS, Phase 2 = PAP, CA cert = the installed ca.pem (or “Do not validate” for testing only; not recommended).
- **Wi‑Fi controller:** The APs use RADIUS (`clients.conf`); endpoints use the profile above. No cert on the AP for TTLS client auth.

Once the CA is trusted and the profile uses EAP-TTLS + PAP with AD credentials, endpoints can connect to the TTLS WiFi.
