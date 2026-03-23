# Sync FreeRADIUS config to the second node (rsync)

---

## For new users: what this is and how it works

### What problem it solves

You have **two FreeRADIUS servers** (Node 1 and Node 2) for high availability. Config and certificates live under `/etc/freeradius/3.0/`. You want **Node 2 to always match Node 1** so both nodes behave the same. This doc describes how to **sync that directory from Node 1 to Node 2** automatically or on demand.

- **Node 1 (source):** The server where you edit config (e.g. `freeradius-node-a`, primary).
- **Node 2 (destination):** The second server that receives a copy of the config (e.g. `192.168.200.22`).

Sync direction is always **Node 1 → Node 2**. Nothing is synced from Node 2 back to Node 1.

### How sync runs (three options)

| Option | When sync runs | Best for |
|--------|----------------|----------|
| **Manual** | You run a script or an rsync command by hand. | One-off copy or testing. |
| **Cron** | A schedule (e.g. every 10 minutes) runs the sync script. | “Keep Node 2 updated even if we don’t restart.” |
| **On every restart** | Every time FreeRADIUS is started or restarted on Node 1, a script runs right after and syncs to Node 2. | “I only change config on Node 1 and restart there; I want Node 2 updated automatically.” |

You can use more than one (e.g. cron plus “on restart”).

### How “sync on every restart” works (recommended)

1. You install a small **systemd drop-in** for `freeradius.service` on Node 1. It adds a single line: after FreeRADIUS starts, run the sync script **as root** (the `+` prefix in systemd does that).
2. The **sync script** (`sync-freeradius-to-node2.sh`) runs **rsync** over SSH: it copies `/etc/freeradius/3.0/` from Node 1 to the same path on Node 2. On Node 2, rsync runs via `sudo` so it can write into `/etc/freeradius/3.0/`.
3. Root on Node 1 uses **SSH keys** to log in to Node 2 (no password). The script uses root’s SSH key and home (`/root/.ssh`), so it must run as root—which the drop-in ensures.
4. If sync fails (e.g. Node 2 is down), the script still exits successfully so that **FreeRADIUS on Node 1 always starts**; only the log shows the sync failure.

So in one sentence: **When you restart FreeRADIUS on Node 1, systemd runs the sync script as root, which rsyncs the config to Node 2 over SSH.**

### Quick start (sync on every restart)

Do this on **Node 1** (replace paths and the Node 2 user/host with yours):

1. **Passwordless SSH from root to Node 2** (one-time):
   ```bash
   sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
   sudo ssh-copy-id -i /root/.ssh/id_ed25519.pub YOUR_USER@NODE2_IP
   ```

2. **On Node 2:** Give that user passwordless `sudo rsync` (see [Passwordless setup](#passwordless-setup-ssh--sudo) below).

3. **Install the sync script and the drop-in on Node 1:**
   ```bash
   sudo cp /path/to/repo/scripts/sync-freeradius-to-node2.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/sync-freeradius-to-node2.sh
   # Edit /usr/local/bin/sync-freeradius-to-node2.sh and set REMOTE_USER and REMOTE_HOST at the top.

   sudo mkdir -p /etc/systemd/system/freeradius.service.d
   sudo cp /path/to/repo/scripts/systemd/freeradius.service.d/sync-after-restart.conf /etc/systemd/system/freeradius.service.d/
   sudo systemctl daemon-reload
   ```

4. **Test:** Restart FreeRADIUS and check the log:
   ```bash
   sudo systemctl restart freeradius
   sudo tail -20 /var/log/freeradius/rsync-sync.log
   ```
   You should see “Starting rsync to …” and “Rsync completed successfully.”

The sections below give the full details: passwordless SSH and sudo, manual rsync command, cron, and the alternative “restart then sync” script.

---

## Prerequisites

- SSH access from Node 1 (source) to Node 2 (e.g. `deploy-user@192.168.200.22`).
- On Node 2, the target user must be able to write to `/etc/freeradius/3.0/`. If that directory is owned by root, run rsync with `--rsync-path="sudo rsync"` so the remote side uses sudo.

## Passwordless setup (SSH + sudo)

So the sync (and systemd/cron) never asks for a password:

### 1. SSH key on Node 1 (run as the user that runs the sync – usually root)

If you don’t have a key yet:

```bash
sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
```

(or use `-t ecdsa` if you prefer). Use an existing key if you already have one.

### 2. Copy the key to Node 2

From Node 1 (as root, or the user that will run the sync):

```bash
ssh-copy-id -i /root/.ssh/id_ed25519.pub deploy-user@192.168.200.22
```

Enter your Node 2 password once. After that, `ssh deploy-user@192.168.200.22` should log in without a password.

### 3. Passwordless sudo on Node 2 (for the user you SSH as)

On **Node 2**, allow that user to run only what the sync needs, without a password:

```bash
sudo visudo
```

Add at the end (replace `deploy-user` with your `REMOTE_USER`):

**If you do NOT use “restart on Node 2 after sync”** (default):

```
deploy-user ALL=(ALL) NOPASSWD: /usr/bin/rsync
```

**If you DO use “restart on Node 2 after sync”** (`RUN_REMOTE_RESTART=1`):

```
deploy-user ALL=(ALL) NOPASSWD: /usr/bin/rsync, /usr/bin/chown, /usr/sbin/systemctl restart freeradius
```

Save and exit. Test from Node 1:

```bash
ssh deploy-user@192.168.200.22 sudo rsync --version
```

(and if you use remote restart: `ssh deploy-user@192.168.200.22 sudo systemctl status freeradius`) — no password should be asked.

## Command (Node 1 → Node 2)

**From Node 1** (replace user and Node 2 IP with yours):

```bash
sudo rsync -avz --delete --rsync-path="sudo rsync" /etc/freeradius/3.0/ deploy-user@192.168.200.22:/etc/freeradius/3.0/
```

- **`-a`** – archive (preserves permissions, ownership where possible).
- **`-v`** – verbose.
- **`-z`** – compress over the wire.
- **`--delete`** – remove files on Node 2 that no longer exist on Node 1 (keeps the tree identical).
- **`--rsync-path="sudo rsync"`** – on the **remote** host, run `rsync` via sudo so it can write under `/etc/freeradius/3.0/`.
- Trailing **`/`** on both paths – sync directory **contents** (not a nested folder).

## If Node 2 user is root

If you SSH as root to Node 2, you can omit `--rsync-path`:

```bash
sudo rsync -avz --delete /etc/freeradius/3.0/ root@192.168.200.22:/etc/freeradius/3.0/
```

## What gets synced

- All config under `/etc/freeradius/3.0/`: `clients.conf`, `mods-enabled/`, `sites-available/`, `sites-enabled/` (symlinks to sites in `sites-available/`), `certs/` (scripts and `.cnf`), etc.
- If you store **certs and keys** in that directory (e.g. `server.key`, `server.pem`, `ca.pem`), they are synced too – both nodes then share the same TLS material.
- **Secrets** (client secrets, LDAP password) are in the config or in separate files; they are synced with the rest. Keep SSH and sudo access restricted.

## After sync

1. On Node 2, fix ownership if needed:  
   `sudo chown -R freerad:freerad /etc/freeradius/3.0/`  
   and `chmod 640` on any `.key` files.
2. Restart FreeRADIUS on Node 2:  
   `sudo systemctl restart freeradius`.

## Optional: exclude certs/keys

If each node has its **own** certs and you only want to sync config (not keys):

```bash
sudo rsync -avz --delete --rsync-path="sudo rsync" \
  --exclude='*.key' --exclude='*.pem' --exclude='*.crt' --exclude='*.p12' \
  /etc/freeradius/3.0/ deploy-user@192.168.200.22:/etc/freeradius/3.0/
```

Then generate or copy certs on Node 2 separately and set permissions there.

---

## Cron script (automatic sync from Node 1)

A script is provided to run the sync from cron on Node 1.

### 1. Install the script on Node 1

```bash
sudo cp /path/to/repo/scripts/sync-freeradius-to-node2.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/sync-freeradius-to-node2.sh
```

### 2. Configure (edit the script or use env)

Edit the variables at the top of the script, or set them in cron:

| Variable | Default | Meaning |
|----------|---------|--------|
| `REMOTE_USER` | `deploy-user` | SSH user on Node 2 |
| `REMOTE_HOST` | `192.168.200.22` | Node 2 IP or hostname |
| `LOCAL_PATH` | `/etc/freeradius/3.0/` | Source on Node 1 |
| `REMOTE_PATH` | `/etc/freeradius/3.0/` | Destination on Node 2 |
| `LOG_FILE` | `/var/log/freeradius/rsync-sync.log` | Log file (script must run with sudo so it can write here) |
| `RUN_REMOTE_RESTART` | `0` | If `1`, after rsync run `chown` and `systemctl restart freeradius` on Node 2 via SSH (requires key-based SSH and passwordless sudo for that user on Node 2) |

### 3. Prerequisites for cron

- **SSH key:** Node 1’s root (or the user running the script) must SSH to `REMOTE_USER@REMOTE_HOST` without a password (e.g. `ssh-copy-id deploy-user@192.168.200.22`).
- **Sudo on Node 2:** `REMOTE_USER` on Node 2 must be able to run `sudo rsync` (and, if `RUN_REMOTE_RESTART=1`, `sudo chown` and `sudo systemctl restart freeradius`) without a password.
- Run the script with **sudo** so it can read `/etc/freeradius/3.0/` and write to `/var/log/freeradius/rsync-sync.log`.

### 4. Add to crontab on Node 1

```bash
sudo crontab -e
```

Example: sync every 10 minutes, log to default file:

```cron
*/10 * * * * /usr/local/bin/sync-freeradius-to-node2.sh
```

Example: sync every 5 minutes with custom target and restart after sync:

```cron
*/5 * * * * REMOTE_HOST=192.168.200.22 RUN_REMOTE_RESTART=1 /usr/local/bin/sync-freeradius-to-node2.sh
```

Check the log:

```bash
sudo tail -f /var/log/freeradius/rsync-sync.log
```

---

## Trigger: sync only after a successful restart

Instead of (or in addition to) cron, you can sync **only when config has changed and the service is running normally** after a restart. Two options:

### Option A: Wrapper script (restart → check → sync)

Use this when you edit config and want to restart and push in one step. The script restarts FreeRADIUS, checks that it is active, then runs the sync. If the config is broken or the service fails to start, sync is not run.

1. Install both scripts on Node 1:

```bash
sudo cp /path/to/repo/scripts/sync-freeradius-to-node2.sh /usr/local/bin/
sudo cp /path/to/repo/scripts/restart-freeradius-and-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/sync-freeradius-to-node2.sh /usr/local/bin/restart-freeradius-and-sync.sh
```

2. After changing config, run:

```bash
sudo restart-freeradius-and-sync.sh
```

The script will:

- Run `freeradius -C` (config test; skip with `RADIUS_CONFIG_TEST=0`).
- Run `systemctl restart freeradius`.
- Wait a few seconds (set `RADIUS_SYNC_WAIT_AFTER_RESTART` if needed).
- If the service is active, run `sync-freeradius-to-node2.sh`.

Same env vars as the sync script apply (`REMOTE_USER`, `REMOTE_HOST`, `RUN_REMOTE_RESTART`, etc.).

### Option B: systemd drop-in (sync on every start/restart)

Every time FreeRADIUS is started or restarted (e.g. `systemctl restart freeradius`), the sync script runs automatically after the service is up. The drop-in uses the **`+` prefix** so the script runs with full privileges (root); no separate unit or sudoers needed. Requires systemd 231+.

1. Install the sync script as above.
2. On **Node 1**, ensure **root** can SSH to Node 2 without a password (sync runs as root):
   ```bash
   sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
   sudo ssh-copy-id -i /root/.ssh/id_ed25519.pub deploy-user@192.168.200.22
   ```
3. Install the drop-in:
   ```bash
   sudo mkdir -p /etc/systemd/system/freeradius.service.d
   sudo cp /path/to/repo/scripts/systemd/freeradius.service.d/sync-after-restart.conf /etc/systemd/system/freeradius.service.d/
   sudo systemctl daemon-reload
   ```
4. From then on, any `systemctl start freeradius` or `systemctl restart freeradius` will run the sync script as root after the service has started.

---

## Troubleshooting

- **Sync not running after restart**  
  Check that the drop-in is in place: `cat /etc/systemd/system/freeradius.service.d/sync-after-restart.conf` should show `ExecStartPost=+/usr/local/bin/sync-freeradius-to-node2.sh`. Run `sudo systemctl daemon-reload` after changing it.

- **“Permission denied (publickey)” or “/etc/freeradius/.ssh” in the log**  
  The script is not running as root (e.g. the `+` prefix is missing in the drop-in). With `+`, the script runs as root and uses `/root/.ssh`. Also ensure root on Node 1 can SSH to Node 2: `sudo ssh -o BatchMode=yes USER@NODE2_IP echo OK`.

- **“Host key verification failed”**  
  The script uses `StrictHostKeyChecking=accept-new`, so the first run should add Node 2’s key. If it still fails, run once as root: `sudo ssh USER@NODE2_IP` and accept the key, then try again.

- **Sync fails but FreeRADIUS still starts**  
  By design the script always exits 0 so the service is not blocked. Check `/var/log/freeradius/rsync-sync.log` (or `journalctl -u freeradius`) for the real error.

- **Node 2 missing files or wrong permissions after sync**  
  On Node 2 run: `sudo chown -R freerad:freerad /etc/freeradius/3.0/` and, if you use the script with `RUN_REMOTE_RESTART=1`, the script will do that and restart FreeRADIUS for you.
