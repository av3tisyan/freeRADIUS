# EAP security and MS-CHAPv2 (hardened setup)

This project’s EAP config is hardened for **security** and **reliability**: TLS 1.2 with strong ciphers. **If NTLM is disabled in your AD**, inner auth uses **PAP + LDAP bind** (password only inside the TLS tunnel); MS-CHAPv2/ntlm_auth is not used.

## Why not inner PAP?

- **PAP** sends the password in cleartext. Inside EAP-TTLS/PEAP it is encrypted on the wire, but:
  - The password is still in the clear inside the tunnel.
  - It’s weaker than a challenge/response method.
- **MS-CHAPv2** sends only a challenge/response; the password never leaves the client. The server verifies it against Active Directory via **ntlm_auth** (Samba winbind).

## What was changed

| Item | Before | After |
|------|--------|--------|
| TTLS inner method | PAP (or MD5) | **MS-CHAPv2** (PAP still available in inner-tunnel as fallback) |
| PEAP | Not configured | **PEAP** with inner MS-CHAPv2 (for Windows/Android) |
| TLS ciphers | `DEFAULT` | Strong only: EECDH+AESGCM, ECDHE-RSA-AES*-GCM, DHE-RSA-AES*-GCM |
| TLS version | 1.2 | 1.2 (unchanged) |
| ECDH curves | (none) | X25519, prime256v1, secp384r1 |
| MS-CHAP verification | — | **rlm_mschap** + **ntlm_auth** against AD |

## Deployment requirement: ntlm_auth (winbind)

For **inner MS-CHAPv2** to work, the FreeRADIUS server must verify the response against AD. That is done by **ntlm_auth**, which requires the server to be joined to the domain and **winbind** to be running.

1. **Join the RADIUS server to AD** (on both HA nodes if you use both for EAP):
   ```bash
   sudo apt install samba winbind
   # Configure /etc/samba/smb.conf: workgroup, realm, security = ads
   sudo net ads join -U <admin-user>
   sudo systemctl enable --now winbind
   ```
2. **Ensure ntlm_auth is available:**
   ```bash
   which ntlm_auth   # usually /usr/bin/ntlm_auth
   ```
3. **mschap** module (`mods-enabled/mschap`) is configured to call `ntlm_auth`. If your AD NetBIOS domain is not the default, add `--domain=YOURDOMAIN` to the `ntlm_auth` line.

## NTLM disabled in AD (current setup)

If NTLM is disabled in your domain (recommended for security), **inner PAP + LDAP bind** is used:

- In `mods-enabled/eap`, `ttls` and `peap` have `default_eap_type = pap`.
- Inner-tunnel uses **PAP** then **LDAP bind** to verify the password; the password is sent only inside the TLS tunnel (encrypted on the wire).
- In `mods-enabled/mschap`, **ntlm_auth** is not configured; MS-CHAPv2 is not used.

## If you cannot use winbind (or NTLM is disabled)

When NTLM is disabled or winbind is not used, the config already uses **PAP + LDAP bind** as above. The password is protected by the outer TLS tunnel; MS-CHAPv2 would be stronger when available.

## Reliability (unchanged)

- **fragment_size = 1000** and **include_length = yes** keep TLS within typical MTU and avoid handshake timeouts over Wi-Fi/VPN.
- **TLS 1.2 only** and strong ciphers reduce protocol and cipher risks.

## Quick test

After deploying and starting winbind:

```bash
# From the RADIUS server
ntlm_auth --username=YOUR_USER --password=YOUR_PASS
# Should succeed if the user is in AD.
sudo radiusd -XC
# Connect a client with EAP-TTLS or PEAP and MS-CHAPv2 inner; check logs.
```
