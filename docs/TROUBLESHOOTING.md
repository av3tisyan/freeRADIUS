# Troubleshooting

## Service won’t start (exit 1 after “Configuration appears to be OK”)

Parsing succeeds but **binding to ports** fails (1812, 1813, 18120, 2083). The journal often hides the real error.

**Debug:**

```bash
sudo systemctl stop freeradius
sudo freeradius -X
```

(`sudo radiusd -X` if your package uses `radiusd`.)

| Message | Meaning | Fix |
|--------|--------|-----|
| `Address already in use` / `Failed to bind` | Port in use | `sudo ss -ulnp \| grep -E '1812|1813|18120'` and `sudo ss -tlnp \| grep 2083`; stop duplicate `freeradius` / `radiusd` |
| `Permission denied` on bind | Capabilities / user | Run service as intended (usually root for bind) |
| PID file errors | `run_dir` / permissions | Fix `/var/run/freeradius` |

**RadSec (2083):** use `sudo freeradius -fxx -l stdout` for TLS/threading-related failures.

---

## Invalid Message-Authenticator from client localhost (proxy)

If FreeRADIUS **proxies** to **127.0.0.1:1812**, the **home server secret** in `proxy.conf` must **match** the **client localhost** secret in `clients.conf`. If they differ:

```text
Received packet from 127.0.0.1 with invalid Message-Authenticator! (from client localhost)
```

Use **one** secret in both `home_server localhost` (proxy.conf) and `client localhost` (clients.conf), then restart FreeRADIUS.
