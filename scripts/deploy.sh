#!/usr/bin/env bash
# Apply this repo to a Pi-hole. RUN ON THE PI-HOLE HOST, as root.
# Refuses to touch anything until tools/qa.py passes.
#
#   sudo bash scripts/deploy.sh            # allowlist + regex, then gravity
#   sudo bash scripts/deploy.sh --dry-run  # print what would change
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }

command -v pihole >/dev/null || { echo "pihole not found -- run this on the Pi-hole host"; exit 1; }
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "== QA gate =="
python3 tools/qa.py >/dev/null 2>&1 || { python3 tools/qa.py; echo; echo "ABORT: QA failed"; exit 1; }
echo "  QA clean"

strip() { grep -hv '^\s*#' "$@" | grep -v '^\s*$'; }

# Allowlist FIRST. Pi-hole applies allow over block, so loading it before the
# regex means there is never a window where a critical domain is blocked.
echo "== allowlist ($(strip allowlist.txt | wc -l | tr -d ' ') domains) =="
while read -r d; do run pihole allow "$d"; done < <(strip allowlist.txt)

echo "== regex ($(strip regex.txt | wc -l | tr -d ' ') patterns) =="
while read -r p; do run pihole regex "$p"; done < <(strip regex.txt)

# This script only ADDS. A domain removed from a list leaves its old regex in
# Pi-hole's database forever unless someone deletes it -- flag those here.
echo "== stale regex check =="
DB=/etc/pihole/gravity.db
if [ -r "$DB" ] && command -v pihole-FTL >/dev/null; then
  STALE=0
  while read -r p; do
    strip regex.txt | grep -qxF "$p" || { echo "  stale -- remove with: pihole regex -d '$p'"; STALE=1; }
  done < <(pihole-FTL sqlite3 "$DB" "select domain from domainlist where type=3;" | grep -F '(\.|^)')
  if [ "$STALE" = 0 ]; then echo "  none"; fi
else
  echo "  skipped (cannot read $DB). If you removed a domain from a list, also run:"
  echo "    pihole regex -d '(\\.|^)that-domain\\.com\$'"
fi

cat <<EOF

== adlists ==
Add these as adlists in the web UI (Admin -> Lists), or with:

  pihole -a adlist add <url>

  https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/temp-email-sites-expanded.txt
  https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/free-proxy-sites-expanded.txt
  https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/adult-chat-sites-expanded.txt

Opt-in (blocks tech-news sites -- read the header first):
  https://raw.githubusercontent.com/Nawter/pihole-blocklists/main/expanded/proxy-listicles-sites-expanded.txt
EOF

echo
echo "== rebuild gravity =="
run pihole -g

echo
echo "Deployed. Verify with: bash scripts/check.sh"
