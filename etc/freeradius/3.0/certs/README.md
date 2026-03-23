# FreeRADIUS certificates

Generate or regenerate certificates for EAP and RadSec. The server cert uses **subjectAltName** (from **xpextensions**) for compatibility with iOS 13+, Android 11+, and Windows 11. Replace `radius.example.com` and `YourOrg` in the `.cnf` files with your domain and organization before running `make` or `bootstrap`.

## 0. Create passwords.mk before first run (required for bootstrap / make)

The stock Makefile can build **passwords.mk** in a way that breaks the `-days` argument. Generate it yourself first:

```bash
cd /etc/freeradius/3.0/certs
sudo bash make-passwords-mk.sh
sudo ./bootstrap
```

If bootstrap fails at **client.p12** with "maybe wrong password" or empty password errors, recreate **passwords.mk** with all required variables (see script or docs), then run `make client`.

## 1. Using the official bootstrap script (first-time or missing certs)

```bash
cd /etc/freeradius/3.0/certs
sudo ./bootstrap
```

Bootstrap only creates files that do **not** exist. After running, set ownership and restart:

```bash
sudo chown freerad:freerad server.key server.crt server.pem ca.pem ca.key
sudo chmod 640 server.key ca.key
sudo systemctl restart freeradius
```

## 2. Using the Makefile (remove all, then rebuild)

Replace your domain in **server.cnf**, **ca.cnf**, and **xpextensions** (e.g. `radius.example.com`), then:

```bash
cd /etc/freeradius/3.0/certs
make destroycerts
make server
```

- **destroycerts** removes existing certs/keys.
- **make server** creates CA and server cert with subjectAltName.

**EAP:** In `mods-enabled/eap` and RadSec `tls` blocks, set `private_key_password` to the passphrase you used in **server.cnf** (or leave empty if the key has no passphrase).

## 3. Using regenerate-certs.sh (no Makefile)

```bash
cd /etc/freeradius/3.0/certs
sudo bash regenerate-certs.sh
```

Produces **server.key**, **server.pem**, **ca.key**, **ca.pem**. Edit **xpextensions** and **server.cnf** for your domain before running if needed.

## Config files

- **ca.cnf** – CA DN and options; edit country, org, commonName, and CRL URL for your environment.
- **server.cnf** – Server cert DN and (optional) passphrase; edit commonName and org.
- **xpextensions** – subjectAltName DNS names; set to your RADIUS hostname(s).
- **client.cnf**, **inner-server.cnf** – Used by the Makefile; edit org and email/commonName as needed.

After any regeneration, set ownership (`chown freerad:freerad` on key/cert files, `chmod 640` on keys) and restart FreeRADIUS.
