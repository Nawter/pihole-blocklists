# Pi-hole Blocklists

DNS blocklists for Pi-hole covering **temp-email services, free proxies/VPNs, and random-chat sites** — plus the regex, allowlist, scripts and QA needed to deploy them without locking yourself out.

## What's here

| File | What it is |
|---|---|
| `temp-email-sites.txt` | Disposable/temporary email frontends (temp mail, 10-minute mail, fake mail generators) |
| `free-proxy-sites.txt` | Free web proxies, site unblockers, proxy-list providers, commercial proxy/scraping vendors |
| `adult-chat-sites.txt` | Adult and random video-chat frontends |
| `proxy-listicles-sites.txt` | **Opt-in.** Tech-news sites blocked only for publishing "top N free proxy" articles |
| `expanded/*.txt` | Generated. Subdomain-expanded hostnames — **subscribable as adlist URLs** |
| `regex.txt` | Generated. `(\.\|^)domain$` patterns — full wildcard coverage, added via CLI/UI |
| `allowlist.txt` | Domains that must never be blocked. Your escape hatch |
| `firewall/proxy-ips.txt` | **Not a Pi-hole file at all.** ~43k IPs for pf/iptables. See below |
| `tools/` | `build.py` generate, `qa.py` gate (Python: this is where the logic lives) |
| `scripts/` | `deploy.sh` push to Pi-hole, `check.sh` diagnose (bash: thin glue over system commands) |
| `Makefile` | front door — `make help` lists everything |
| `local-mac/` | run the same lists on a single Mac with no Pi-hole |


## The three forms, and which to use

Every list exists in three shapes because Pi-hole treats them differently:

| Form | How Pi-hole takes it | Auto-updates? | Covers subdomains? |
|---|---|---|---|
| `*-sites.txt` | adlist URL | yes, on `pihole -g` | no — exact match only |
| `expanded/*.txt` | adlist URL | yes, on `pihole -g` | common prefixes only |
| `regex.txt` | regex table (CLI/UI/API) | **no** — must be reloaded | yes, all subdomains |

The catch that drives this design: **Pi-hole cannot subscribe to a remote regex list.** The adlist field accepts domain and hosts formats only. Regex entries have to be pushed into the database via `pihole regex`, the web UI, or the API — there is no URL you can paste.

So `expanded/` is the zero-setup option: paste a URL, done, and it refreshes itself. `regex.txt` is the complete option but needs `scripts/deploy.sh` (or manual paste) and a re-run whenever the lists change.

**Use both.** They overlap, which is fine — Pi-hole doesn't care if a domain is blocked twice. `expanded/` handles the everyday case with no maintenance; regex catches what prefix-guessing can't. `flirtify.com` serves **wildcard DNS** — every subdomain you can invent resolves — so only the regex genuinely covers it.

### Why there's a build step

The hand-edited source is one bare domain per line in `*-sites.txt`. The expanded and regex forms are mechanical derivations. `tools/build.py` generates them so you edit one file instead of three and they can't drift apart. It is not a deployment tool and it never touches Pi-hole.

## Install

```bash
git clone https://github.com/Nawter/pihole-blocklists.git
cd pihole-blocklists
```

**1. Add the adlists** (Admin → Lists in v6, Group Management → Adlists in v5) — same place you'd paste StevenBlack's list:

```
https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/temp-email-sites-expanded.txt
https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/free-proxy-sites-expanded.txt
https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/adult-chat-sites-expanded.txt
```

Opt-in — blocks tech-news sites, read the file header first:

```
https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/proxy-listicles-sites-expanded.txt
```

The bare `*-sites.txt` at repo root are the **hand-edited source**, not something
you subscribe to. They exist because `expanded/` is 5,900 lines you can't sensibly
edit and because `regex.txt` is generated from them. Edit those; subscribe to these.

**2. Load the allowlist and regex, then rebuild gravity** — on the Pi-hole host:

```bash
sudo bash scripts/deploy.sh --dry-run   # see what it would do
sudo bash scripts/deploy.sh
```

`deploy.sh` runs the QA suite first and **refuses to touch Pi-hole if QA fails**. It loads the allowlist *before* the regex, so there's never a window where a critical domain is blocked.

This is not one-and-done: the adlist URLs refresh themselves on every `pihole -g`, but the regex table doesn't — re-run `make deploy` on the Pi-hole host whenever the repo's lists change (see "Editing the lists").

**3. Verify**, from any machine using the Pi-hole as its resolver:

```bash
make check DNS=192.168.1.x
```

This checks both directions: that the proxy/temp-mail sites are actually blocked, *and* that Anthropic, GitHub, npm, PyPI, Apple, Microsoft, Zoom, Slack and Cloudflare still resolve.

## When something breaks after deployment

This will happen. Blocklists over-reach, and one of these lists is built from scraped data.

**Diagnose:**

```bash
make check DOMAIN=some-site.com
```

It tells you whether this repo is responsible (exact entry, or which regex pattern matched), whether it's already allowlisted, and what to do next. If it isn't us, it points you at `pihole -q`, the upstream adlists, the client's `/etc/hosts`, and browser DoH.

**Unblock immediately** — takes effect at once, no gravity rebuild:

```bash
pihole allow some-site.com
```

Allow beats block in Pi-hole: an exact allow entry wins over gravity *and* over regex.

**Make it permanent** so it survives the next deploy — add the domain to `allowlist.txt` (keeps the parent blocked, exempts this host) or delete it from the `*-sites.txt` (stops blocking it entirely). Then:

```bash
make build && make qa
```

If you deleted a domain from a list, one more step on the Pi-hole: `deploy.sh` only *adds* entries, so the old regex stays in Pi-hole's database until you remove it — `deploy.sh` flags stale patterns on its next run, or delete it yourself:

```bash
pihole regex -d '(\.|^)some-site\.com$'
```

(The same applies in reverse to `pihole allow` entries: removing a domain from `allowlist.txt` doesn't un-allow it on the Pi-hole.)

**Nuclear option** — disable everything for 5 minutes while you think:

```bash
pihole disable 5m
```

## Editing the lists

```bash
$EDITOR free-proxy-sites.txt     # one bare domain per line, no scheme, no path
make build            # regenerate expanded/ + regex.txt, sort sources
make qa               # must pass
git commit -am "add foo.com"
git push
```

Then, on the Pi-hole host — the regex table doesn't update itself:

```bash
git pull && make deploy
```

`make build` never touches `firewall/proxy-ips.txt` — that file is regenerated separately with `make refresh-ips` (see `local-mac/refresh-ips.py`).

## QA

`tools/qa.py` exists for one reason: **never block ourselves.** It exits non-zero on any failure and gates `deploy.sh`.

| Group | Checks |
|---|---|
| Format | bare lowercase domains only; no schemes/paths/ports/wildcards; no raw IPs |
| Hygiene | no duplicates, sorted, no domain in two core lists |
| Public suffix | hard-fails if a bare TLD or a suffix like `co.uk` is ever blocked |
| Allowlist integrity | nothing both blocked and allowed; **no regex pattern matches an allowlisted domain** |
| Critical smoke test | 24 hardcoded must-resolve hosts, checked against exact lists *and* every regex |
| Regex validity | all patterns compile, all anchored, each matches its own domain and subdomains but **not** lookalikes (`foo.com` must not match `evilfoo.com`) |
| Expanded lists | every base domain survives expansion; no allowlisted or critical host present; still well formed |
| Freshness | derived files are in sync with the sources (`build.py --check`) |

Run them with `make qa`.

The critical smoke test is deliberately hardcoded in `tools/lists.py` rather than read from `allowlist.txt` — if someone deletes a line from the allowlist, the smoke test still catches it.

The suite is validated by fault injection: a critical domain, a public suffix, a URL, an unanchored regex, broken regex syntax, an allowlist conflict, a stale derived file, and a base domain dropped from its expansion. Each one must fail the build. Two of these caught real bugs in earlier versions of the tooling itself — which is why `build.py` and `qa.py` are Python rather than shell. The awk-based builder silently produced *zero* expansions twice (`gsub` mutating its record, then counting non-dot characters instead of dots) while still exiting 0.

## Running it on a Mac without Pi-hole

See [`local-mac/README.md`](local-mac/README.md). Short version:

```bash
make build
make refresh-upstream   # optional: hagezi's ~90k hostnames for /etc/hosts
make hosts-on           # domains via /etc/hosts (~10.5k, ~100k with upstream)
make pf-on              # IPs via pf (optional)
make status
```

`local-mac/` uses `expanded/` because `/etc/hosts` has no wildcards, and it carries
`refresh-ips.py` so `firewall/proxy-ips.txt` can be regenerated from scratch on any
machine — the repo is self-contained. `make refresh-upstream` is the Mac-only
substitute for subscribing to hagezi: Pi-hole takes hagezi as an adlist (see
[Scope](#scope)), but `/etc/hosts` can't subscribe to anything, so the list is
fetched, prefix-expanded and included by `hosts-on` instead.

## Scope

These lists block service **frontends**. They complement — do not replace — the big maintained lists. Add these as adlists too:

- [hagezi/dns-blocklists](https://github.com/hagezi/dns-blocklists) — `doh-vpn-proxy-bypass`, DoH resolvers, VPN and proxy endpoints (~17.6k domains)
- [disposable-email-domains](https://github.com/disposable-email-domains/disposable-email-domains) — the email domains themselves
- [7c/fakefilter](https://github.com/7c/fakefilter) — same, larger

### Adding hagezi to Pi-hole

Pi-hole subscribes to it directly — nothing to generate or vendor. In the web UI (Admin → Lists in v6, Group Management → Adlists in v5) paste:

```
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt
```

Or from the Pi-hole host:

```bash
pihole -a adlist add https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt "hagezi doh-vpn-proxy-bypass"
pihole -g
```

Use the **`domains/`** URL for Pi-hole adlists, not `wildcard/`. Hagezi's `wildcard/` files are bare registrable domains for blockers that expand subdomains themselves; the `domains/` files carry the subdomains explicitly, which is what the adlist parser expects. Combined with this repo's regex table you get full coverage either way. Neither format is usable as-is in `/etc/hosts` — that's what `make refresh-upstream` is for on a Mac (see below).

## Deliberately not included

Judgement calls, documented so they aren't silently re-litigated:

- **`portswigger.net`** (Burp Suite), **`telerik.com`** (Fiddler) — HTTP intercepting proxies for debugging and security testing, not circumvention services. Telerik is also a general dev-tools vendor.
- **`ipqualityscore.com`** — a proxy *detection* service. Blocking it works against you.
- **`adguard.com`**, **`internxt.com`**, **`simplelogin.io`**, **`addy.io`**, **`relay.firefox.com`** — legitimate products that happen to offer a temp-mail or aliasing feature. Commented out at the bottom of `temp-email-sites.txt`; uncomment at your own risk.
- **Tech-news sites** — moved to `proxy-listicles-sites.txt` as opt-in rather than merged into the main lists. Blocking TechRadar or BleepingComputer because they ran a proxy listicle is a defensible personal choice and an indefensible default.

## About `firewall/proxy-ips.txt` — this does NOT go into Pi-hole

**There is no field in Pi-hole for this file.** Not an adlist, not the regex box, not the allowlist. Pi-hole is a DNS server: it answers name lookups and can only act on names. An IP address never passes through it, so it has nothing to match against.

This file is for a **firewall**. Pick whichever you actually run:

**On the Pi-hole host** (blocks traffic that the Pi forwards — only useful if the Pi is your router/gateway):

```bash
sudo ipset create proxyblock hash:ip maxelem 65536
grep -v '^#' firewall/proxy-ips.txt | while read -r ip; do sudo ipset add proxyblock "$ip" -exist; done
sudo iptables -I FORWARD -m set --match-set proxyblock dst -j DROP
sudo apt install iptables-persistent   # otherwise it dies on reboot
```

**On your router** — if it runs OpenWrt/pfSense/OPNsense, import as an IP alias or ipset. This is the only placement that covers every device on the network.

**On a single Mac** (what this file was originally built for):

```bash
# /etc/pf.conf
table <proxyblock> persist file "/path/to/firewall/proxy-ips.txt"
block drop out quick to <proxyblock>
```

```bash
sudo pfctl -n -f /etc/pf.conf    # parse only, loads nothing
sudo pfctl -f /etc/pf.conf && sudo pfctl -E
curl -sS -o /dev/null -w '%{http_code}\n' https://api.anthropic.com/v1/messages   # expect 401, not a hang
```

pf does not persist across reboot on macOS without a LaunchDaemon.

**If you only run Pi-hole and no firewall, skip this file entirely.** The DNS lists do the useful work; the IP list is a bonus layer that catches proxies reached by raw IP, which DNS blocking structurally cannot.

Two warnings before you load it anywhere, both learned the hard way:

1. **It is scraped data, and it contained Anthropic's range.** Loading an earlier version broke `api.anthropic.com`. Cloudflare (~11k addresses), AWS (~4.4k), Google Cloud, Fastly and the public resolvers `8.8.8.8` / `1.1.1.1` were in there too. Those ranges are filtered out now, but **verify against your own critical hosts first:**

```bash
for h in api.anthropic.com github.com your-vpn-gateway.example.com; do
  dig +short $h | while read -r ip; do
    grep -qxF "$ip" firewall/proxy-ips.txt && echo "WOULD BLOCK $h ($ip)"
  done
done
```

2. **Blocking shared infrastructure has a huge blast radius.** One IP can front thousands of unrelated sites. The filtering is a blunt instrument, not a guarantee.

## Repeatable setup / teardown

Everything is regenerable from a clean clone — there is no hidden state and no
scratch directory to carry between machines:

```bash
git clone https://github.com/Nawter/pihole-blocklists.git && cd pihole-blocklists
make build          # expanded/ + regex.txt
make refresh-ips FULL=1        # firewall/proxy-ips.txt (optional)
make qa             # 18 checks, must pass
```

Then deploy to Pi-hole (`scripts/deploy.sh`) or to a single Mac
(`local-mac/macblock.sh hosts-on`). To tear down: `pihole disable`, or
`sudo bash local-mac/macblock.sh hosts-off && sudo bash local-mac/macblock.sh pf-off`.


## Restricting or Disabling Tor in Brave via Folder Permissions

You can change permissions or restrict the Tor folder in Brave by locating the
browser's profile directory on your operating system and modifying folder access
or permissions via the command line. ([source](https://community.brave.app/t/how-to-disable-tor-browser-permanent/470734))

### Finding the Tor Directory

- **Windows:** `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data`
- **macOS:** `~/Library/Application Support/BraveSoftware/Brave-Browser`
- **Linux:** `~/.config/BraveSoftware/Brave-Browser`

Sources: [cleanbrowsing](https://cleanbrowsing.org/support/troubleshooting/disable-tor-brave),
[GitHub issue #454](https://github.com/brave/brave-browser/issues/454),
[Brave Community](https://community.brave.app/t/how-to-disable-tor-browser-permanent/470734)

### Modifying Permissions

- **Close Brave:** Ensure the browser is completely shut down before altering files.
- **Locate Tor files:** Find the specific Tor profile or executable subfolder inside
  your user data profile path.
- **Remove permissions (Linux/macOS):** Run a terminal command such as `chmod -rwx tor`
  on the target directory to revoke read, write, and execute permissions if you want
  to block Tor functionality.
- **Adjust security properties (Windows):** Right-click the folder, go to
  **Properties > Security**, and edit user/administrator permissions to restrict access.

## Known limits

- **Browser DoH bypasses Pi-hole entirely.** Chrome and Firefox "Secure DNS" resolve names themselves. If a site loads despite being blocked, check that first. Blocking DoH endpoints (hagezi's list, or firewalling port 853) is the counter.
- **DNS blocking is domain-level.** It can't stop a proxy reached by raw IP — that's what `firewall/proxy-ips.txt` is for.
- **Free proxy sites churn constantly.** Expect these lists to need refreshing.

## Contributing

One bare domain per line, sorted, no `http://`, no paths. Run `make build && make qa` before opening a PR — there's no CI here, the QA suite is the gate.
