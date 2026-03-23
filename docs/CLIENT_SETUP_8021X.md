# Client setup for 802.1X (Wi‑Fi and wired)

EAP-TTLS with PAP, anonymous outer identity, and Root CA trust. Use the same CA as your FreeRADIUS server (e.g. `etc/freeradius/3.0/certs/ca.pem`).

**Sanitized example configs (no secrets, no real CA):** [client-configs/](../client-configs/README.md) — copy and replace placeholders before use.

---

## 1. macOS: Universal Profile (.mobileconfig)

One profile can contain **Root CA**, **Wi‑Fi**, and **Wired Ethernet**. Identity Privacy and Keychain are used.

- **Example (no sensitive data):** [client-configs/macos/8021X.mobileconfig.example](../client-configs/macos/8021X.mobileconfig.example)
- **Before install:** Replace the Root CA `<data>` payload with the **base64 of your** `ca.pem` (e.g. `base64 -i ca.pem | tr -d '\n'`). Replace `YOUR_WIFI_SSID` with your SSID if needed.
- The example sets **OneTimePassword** = false so the password is saved to Keychain (“Remember” works). If your profile keeps asking for the password, see [WIFI_8021X_TROUBLESHOOTING.md](WIFI_8021X_TROUBLESHOOTING.md).
- Copy to a Mac and open the `.mobileconfig` to install.

---

## 2. Windows: OMA-URI (Wi‑Fi profile)

For your **MDM** (e.g. Intune, Jamf): use a Custom Configuration Policy to deploy the Wi‑Fi profile via CSP.

- **OMA-URI:** `./Device/Vendor/MSFT/WiFi/Profile/YourSSID/WlanXml` (use your SSID in the profile name).
- **WlanXml value:** Use [client-configs/windows/WiFi-Test-RADIUS.xml.example](../client-configs/windows/WiFi-Test-RADIUS.xml.example); replace `YOUR_WIFI_SSID` with your SSID. No secrets in the XML (EAP type 21 = TTLS, PAP, anonymous identity).

---

## 3. Linux: nmcli (Wi‑Fi and wired)

Use NetworkManager. You need the RADIUS Root CA on the client (e.g. copy `ca.pem` from the server).

- **Wired:** [client-configs/linux/wired-8021x.example.sh](../client-configs/linux/wired-8021x.example.sh) — set `CA_CERT`, `IDENTITY`, `INTERFACE` (e.g. `eth0`), then run with `sudo`.
- **Wi‑Fi:** [client-configs/linux/wifi-8021x.example.sh](../client-configs/linux/wifi-8021x.example.sh) — set `CA_CERT`, `IDENTITY`, `SSID`, then run with `sudo`.

One-liner examples (replace placeholders):

```bash
# Wired
sudo nmcli connection add type ethernet con-name "Wired-8021X" ifname eth0 \
  802-1x.eap ttls 802-1x.phase2-auth pap \
  802-1x.identity "YOUR_AD_USERNAME" 802-1x.anonymous-identity "anonymous" \
  802-1x.ca-cert /path/to/ca.pem

# Wi-Fi
sudo nmcli connection add type wifi con-name "WiFi-8021X" ssid "YOUR_SSID" \
  802-11-wireless-security.key-mgmt wpa-eap \
  802-1x.eap ttls 802-1x.phase2-auth pap \
  802-1x.identity "YOUR_AD_USERNAME" 802-1x.anonymous-identity "anonymous" \
  802-1x.ca-cert /path/to/ca.pem
```
