# CLAUDE.md — pihole-blocklists charter

Curated DNS blocklists (temp email, free proxies/VPNs, adult chat) plus the
tooling to deploy them without locking yourself out. Hand-edited sources are
the `*-sites.txt` at repo root; `expanded/` and `regex.txt` are **generated
and committed** (they back published raw.githubusercontent adlist URLs).
Logic lives in `tools/*.py`; `scripts/*.sh` and `local-mac/macblock.sh` are
thin glue over system commands.

## Commands

- Build: `make build` — regenerate `expanded/` + `regex.txt` from the sources
- QA: `make qa` — 18 checks, gates deploy; `make test` for the pytest form
- Diagnose: `make check DOMAIN=foo.com` or `make check DNS=<pihole-ip>`
- Deploy (on the Pi-hole host): `make deploy`
- Single Mac: `make hosts-on|hosts-off|pf-on|pf-off|status|refresh-ips`

## How to talk to the user

**Always give honest, constructive feedback — never just agree to be nice.**
When asked for an opinion or review, lead with the truthful assessment even
when it's negative ("this isn't worth doing because…", "this will break
when…"). Flag over-engineering, wasted effort, and risks unprompted. If a
request has a better alternative, say so before implementing. The user
explicitly wants candor and forgets to ask for it each time — this rule is
the standing request.

## Workflow guardrails

1. **`make build && make qa` gate every commit.** Editing a `*-sites.txt`
   without rebuilding leaves `expanded/`/`regex.txt` stale — QA's freshness
   check catches this; never bypass it. Commit sources and derived files
   together. Never push red.
2. **Never delete or `git rm` `expanded/` or `regex.txt`.** Subscribers'
   adlist URLs 404 the moment a deletion is pushed. `make clean` is
   deliberately limited to Python caches.
3. **Docs stay in sync:** a change that alters counts, commands, or script
   behavior updates `README.md` / `local-mac/README.md` in the same commit.
   All docs reference `make` targets, not script paths that may move.
4. **Simplicity:** smallest change that works; stdlib before new code; no
   new dependencies without asking.

## Safety guardrails — never weaken without explicit user approval

- **Never block critical hosts.** `allowlist.txt` plus the hardcoded CRITICAL
  set in `tools/lists.py` are the escape hatch; QA hard-fails if any list or
  regex matches them. Don't remove entries from either without being asked.
- **Scripts that touch system files (`/etc/hosts`, `/etc/pf.conf`) must:**
  back up first; manage only their own marked block (never strip other
  tools' entries); and for pf, syntax-check a candidate before writing and
  keep included files under `/etc/pf.anchors/`, never inside the clone — a
  dangling include makes pf load nothing at boot.
- **`refresh-ips.py` must never write an empty or Anthropic-containing
  list.** The 0-kept abort and the `160.79.` assert stay; writes stay
  atomic (`os.replace`).
- **`deploy.sh` is add-only by design** and must keep printing its stale-
  regex report — it never auto-deletes Pi-hole entries (users' own
  `(\.|^)…$` patterns are indistinguishable from ours).
- QA checks are the product. Fixing a red build by loosening a check needs
  explicit user approval.

## Known constraints (don't "fix" silently)

- **Pi-hole cannot subscribe to a remote regex list** — that's why every
  list exists in three forms (bare source, `expanded/`, `regex.txt`).
- **`proxy-listicles-sites.txt` is opt-in and gets no regex** (excluded
  from CORE_LISTS in `tools/lists.py`) — deliberate, not a bug.
- `/etc/hosts` has no wildcards; `expanded/` is the ceiling on a Mac,
  Pi-hole regex is the real fix (`flirtify.com` serves wildcard DNS).
- `firewall/proxy-ips.txt` is scraped data for firewalls only — it never
  goes into Pi-hole, and it once contained Anthropic's IP range.
- The "Deliberately not included" section of README.md documents judgement
  calls (portswigger, ipqualityscore, …) — don't re-add those domains.
