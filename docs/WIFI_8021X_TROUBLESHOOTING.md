# Wi‑Fi 802.1X troubleshooting

Random credential prompts, re-authentication, and “Remember password” not working.

---

## A. Random prompts / re-auth too often

Usually **re-authentication** from RADIUS **Session-Timeout**, the controller’s re-auth interval, or the client not saving the password.

### 1. RADIUS: long Session-Timeout for Wi‑Fi

In **default** `post-auth`, only for your wireless NAS shortname (e.g. `wifi-nas`):

```text
if (&request:Client-Shortname =~ /wifi-nas/) {
    update reply {
        &Session-Timeout := 86400
    }
}
```

Use `86400` (24 h) or longer. Or omit Session-Timeout and let the controller decide.

### 2. Controller

Set 802.1X **re-authentication** to **Never** or a long interval (or “Use RADIUS” if it honors Session-Timeout).

### 3. Client

Ensure the profile allows saving credentials and the user chooses **Remember** / Keychain (see section B).

| Layer | Action |
|-------|--------|
| FreeRADIUS | `Session-Timeout` for Wi‑Fi NAS shortname in default post-auth |
| AP/controller | Long or disabled re-auth interval |
| Client | Saved password / Keychain |

Restart FreeRADIUS after policy changes.

---

## B. Password asked every time / “Remember” doesn’t work

### 1. macOS / iOS: OneTimePassword = false

In **EAPClientConfiguration** (`.mobileconfig`):

```xml
<key>EAPClientAllowPasswords</key><true/>
<key>OneTimePassword</key><false/>
```

If **OneTimePassword** is **true**, the device prompts every time. See [client-configs/macos/8021X.mobileconfig.example](../client-configs/macos/8021X.mobileconfig.example).

### 2. Choose Remember in Keychain

When prompted, pick **Remember** / **Save to Keychain**. If you chose **Never** before, remove the network or profile and reconnect, then choose Remember.

### 3. User vs system profile (macOS)

Prefer **user-level** Wi‑Fi profiles so the password stores in the user Keychain. System/MDM device profiles sometimes cannot save passwords.

### 4. Optional: password in profile (less secure)

**UserPassword** in the profile avoids prompts but exposes the password in the profile—use only if you accept that risk.

### 5. After profile changes

Remove the old profile, install the updated one, connect, enter password once, choose Remember.

---

## Related

- [CLIENT_SETUP_8021X.md](CLIENT_SETUP_8021X.md) – building profiles  
- [BOOTSTRAP_AND_DEPLOYMENT.md](BOOTSTRAP_AND_DEPLOYMENT.md) – EAP-TTLS on clients  
