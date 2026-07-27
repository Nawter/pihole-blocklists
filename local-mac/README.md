# local-mac — run these blocklists on a single Mac, no Pi-hole

Everything here is self-contained: clone the repo on any Mac, run two commands, done. This replaces the ad-hoc `~/proxy-lists` scratch directory that this repo grew out of.

## Setup on a new Mac

```bash
git clone https://github.com/Nawter/pihole-blocklists.git
cd pihole-blocklists
make build                                  # generate expanded/ + regex.txt
sudo bash local-mac/macblock.sh hosts-on    # block the domains
bash local-mac/macblock.sh status           # confirm
```

That's the whole thing. `hosts-on` writes ~10.5k hostnames (~11.7k with the opt-in listicles list) into `/etc/hosts` between `# BEGIN pihole-blocklists` markers. It only ever touches its own marked block — entries written by other tools are left alone.

## Commands

| Command | What it does |
|---|---|
| `bash macblock.sh status` | what's active, plus a 4-domain resolution test. No sudo |
| `sudo bash macblock.sh hosts-on` | write the domain block into `/etc/hosts` |
| `sudo bash macblock.sh hosts-off` | remove it |
| `sudo bash macblock.sh pf-on` | load the IP list into the pf firewall |
| `sudo bash macblock.sh pf-off` | unload it |
| `python3 refresh-ips.py` | refresh `../firewall/proxy-ips.txt` from the internet |

`hosts-on` and `hosts-off` are **idempotent**. They replace one marked block rather than appending, so running `hosts-on` five times leaves you with one copy, not five. Every run backs up to `/etc/hosts.bak.<timestamp>` first.

To include the opt-in tech-news list:

```bash
sudo INCLUDE_LISTICLES=1 bash local-mac/macblock.sh hosts-on
```

## Why this uses `expanded/` and not the bare lists

`/etc/hosts` has **no wildcards**. It matches exact hostnames only, so a line for `blockaway.net` does not block `www.blockaway.net`. That's why `expanded/` exists — it pre-generates the `www.`, `free.`, `app.` … variants that a hosts file can't derive for itself.

It's still not complete. `flirtify.com` serves wildcard DNS, so any subdomain resolves and no finite list covers it. On a Mac this is the ceiling; Pi-hole's regex table is the real fix. If a proxy site loads anyway:

```bash
grep -x '<hostname>' ../expanded/*.txt      # is it even in the list?
```

If it's missing, add the base domain to the relevant `../*-sites.txt`, then `make -C .. build && sudo bash macblock.sh hosts-on`.

## The IP layer (`pf-on`) — optional, and read this first

`pf-on` blocks ~43k proxy **IP addresses**, catching proxies reached by raw IP that DNS blocking structurally cannot. It's genuinely optional; the domain blocking does most of the work.

Two things it does to protect you:

1. **It refuses to load if `api.anthropic.com` or `github.com` resolve into the block list.** This is not theoretical — an earlier version of that list contained Anthropic's `160.79.104.0/23` range and broke Claude Code entirely.
2. **It appends an `include` line to `/etc/pf.conf` rather than replacing the file.** Loading a ruleset with `pfctl -f <file>` *flushes the entire main ruleset*, which removes Apple's anchors and can break GlobalProtect, Internet Sharing and AirDrop. Apple's own comments in `/etc/pf.conf` warn about this. The candidate `pf.conf` is syntax-checked **before** the real file is touched, and the included files are installed under `/etc/pf.anchors/` — not inside the git clone — so moving or deleting the clone can never leave `/etc/pf.conf` pointing at a file that no longer exists (a dangling include makes pf load *nothing* at boot).

**pf does not survive reboot.** macOS reloads `/etc/pf.conf` at boot but deliberately leaves pf disabled. To make it persistent, create `/Library/LaunchDaemons/local.proxyblock.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.proxyblock</string>
  <key>ProgramArguments</key>
  <array><string>/sbin/pfctl</string><string>-E</string><string>-f</string><string>/etc/pf.conf</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
```

```bash
sudo chown root:wheel /Library/LaunchDaemons/local.proxyblock.plist
sudo launchctl load -w /Library/LaunchDaemons/local.proxyblock.plist
```

`/etc/hosts` changes persist on their own and need none of this.

## Refreshing the IP list

```bash
python3 refresh-ips.py           # fast: ~2.5k IPs, small download
python3 refresh-ips.py --full    # ~43k IPs, ~200 MB download
```

Filtering runs in three stages: `ip-allowlist.txt` prefixes first, then loopback/RFC1918/link-local/multicast, then CDN and public-resolver ranges. The script asserts no `160.79.` address survives and refuses to write the file otherwise.

**Add your VPN gateway to `ip-allowlist.txt` before running this.** Find it with:

```bash
ifconfig | grep -A3 utun | grep 'inet '
```

## When something breaks

```bash
bash macblock.sh status                     # is it even us?
grep -x '<hostname>' ../expanded/*.txt      # domain layer
grep -qxF '<ip>' ../firewall/proxy-ips.txt  # IP layer
```

**Undo:**

```bash
sudo bash macblock.sh hosts-off     # drop all domain blocking
sudo bash macblock.sh pf-off        # drop all IP blocking
```

That's a complete undo. Don't restore the *newest* `/etc/hosts.bak.*` afterwards — every run (including `hosts-off` itself) makes a backup first, so the newest one is the blocked file you just removed. If you ever need a pre-install hosts file, pick one by timestamp from `ls -lt /etc/hosts.bak.*`.

**Permanent fix** — remove the domain from `../*-sites.txt` (or add its IP prefix to `ip-allowlist.txt`), then rebuild and reapply.

## Migrating from an older `~/proxy-lists` install

If a previous setup wrote its own block into `/etc/hosts` (a different marker, or
loose `0.0.0.0` lines), `macblock.sh status` will say so. `hosts-on` deliberately
does **not** touch those lines — it manages only its own marked block, so it can't
destroy another tool's hosts-based blocking. To clean up after an old install,
delete its lines yourself (or restore a backup taken *before* it was installed):

```bash
sudo $EDITOR /etc/hosts                     # remove the old install's 0.0.0.0 lines
sudo killall -HUP mDNSResponder
bash macblock.sh status                     # should say "not installed"
sudo bash macblock.sh hosts-on              # apply from this repo
```

Then the old directory can go:

```bash
rm -rf ~/proxy-lists
```

Nothing is lost — `refresh-ips.py` regenerates the IP list, and the curated domains
live in the `*-sites.txt` at repo root. If the old setup also added an `include`
line to `/etc/pf.conf` pointing at that directory, delete it: `pf-on` writes its own.

## Known limits

- **Browser DoH bypasses `/etc/hosts` entirely.** Chrome and Firefox "Secure DNS" resolve names themselves. If a blocked site loads, check that setting before assuming the list is wrong.
- **No wildcards.** Covered above — a Mac limitation, not a bug in the lists.
- **Per-machine.** Every Mac needs its own install. Pi-hole covers a whole network from one place; that's the reason to prefer it if you have somewhere to run it.
- **No upstream lists.** Pi-hole users subscribe to [hagezi's](https://github.com/hagezi/dns-blocklists) ~17.6k VPN/proxy/DoH domains as an extra adlist. This folder only applies *this repo's* ~10.5k hostnames, so coverage is genuinely narrower here. Pulling hagezi into `/etc/hosts` would mean vendoring and expanding a list that updates weekly — deliberately not done.
