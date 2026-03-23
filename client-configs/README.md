# Client configs for 802.1X (no sensitive data)

Example configs for Wi‑Fi and wired 802.1X with EAP-TTLS/PAP and anonymous outer identity. **No secrets, no real CA certs, no org-specific identifiers**—replace placeholders before use.

| File | Platform | What to replace |
|------|----------|-----------------|
| [macos/8021X.mobileconfig.example](macos/8021X.mobileconfig.example) | macOS | Root CA: replace the `<data>` payload with base64 of your `ca.pem`. SSID/display names if desired. |
| [windows/WiFi-Test-RADIUS.xml.example](windows/WiFi-Test-RADIUS.xml.example) | Windows (MDM/OMA-URI) | SSID if different; deploy via your MDM. |
| [linux/wired-8021x.example.sh](linux/wired-8021x.example.sh) | Linux (nmcli) | `YOUR_AD_USERNAME`, `/path/to/ca.pem`, `eth0` interface name. |
| [linux/wifi-8021x.example.sh](linux/wifi-8021x.example.sh) | Linux (nmcli) | `YOUR_AD_USERNAME`, `/path/to/ca.pem`, SSID if different. |

See [docs/CLIENT_SETUP_8021X.md](../docs/CLIENT_SETUP_8021X.md) for full instructions.
