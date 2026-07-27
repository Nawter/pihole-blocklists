#!/usr/bin/env bash
# Live-state checker. Two modes:
#   check.sh [pihole-ip]        verify a deployment: blocks work, critical hosts resolve
#   check.sh <domain>           explain why that domain is blocked, and how to undo it
set -uo pipefail
cd "$(dirname "$0")/.."
strip() { grep -hv '^\s*#' "$@" | grep -v '^\s*$'; }

ARG="${1:-}"
# an argument with letters in the last label is a domain; anything else is a resolver IP
if printf '%s' "$ARG" | grep -qE '[a-zA-Z]'; then
  D=$(echo "$ARG" | tr 'A-Z' 'a-z' | sed -E 's#^https?://##; s#/.*##; s/:[0-9]+$//')

echo "domain: $D"
HIT=0

echo
echo "== resolution now =="
a=$(dig +short +time=3 "$D" 2>/dev/null | head -1)
case "$a" in
  ""|0.0.0.0|::) echo "  BLOCKED (no answer / null route)";;
  *)             echo "  resolves to $a -- not currently blocked by DNS";;
esac

echo
echo "== this repo's exact lists =="
for f in *-sites.txt; do
  strip "$f" | grep -qx "$D" && { echo "  $f: exact entry '$D'"; HIT=1; }
done
[ "$HIT" = 0 ] && echo "  no exact match"

echo
echo "== this repo's regex =="
if [ -f regex.txt ]; then
  m=$(strip regex.txt | while read -r p; do echo "$D" | grep -qE "$p" && echo "  $p"; done)
  [ -n "$m" ] && { echo "$m"; HIT=1; } || echo "  no regex match"
fi

echo
echo "== allowlist =="
strip allowlist.txt | grep -qx "$D" && echo "  present -- should already be exempt" || echo "  not present"

echo
if [ "$HIT" = 1 ]; then
  cat <<EOF
== this repo blocks it. To fix ==

Immediate (on the Pi-hole, effective at once, no gravity rebuild):
  pihole allow $D

Permanent (so it survives the next deploy) -- pick one:
  a) add "$D" to allowlist.txt          # keep blocking the parent, exempt this host
  b) remove "$D" from the *-sites.txt   # stop blocking it entirely
     (then ALSO delete its old regex on the Pi-hole: pihole regex -d '(\.|^)${D//./\\.}\$'
      -- deploy.sh only adds, it never removes)
then: make build && make qa && git commit
EOF
else
  cat <<EOF
== not this repo ==

Check the other sources, in order:
  1. pihole -q $D                       # which adlist/gravity entry matched
  2. upstream adlists (hagezi, disposable-email-domains, fakefilter)
  3. /etc/hosts on the client machine    # ~/proxy-lists writes a block here too
  4. browser DoH -- Chrome/Firefox "Secure DNS" bypasses Pi-hole entirely
EOF
fi
  exit 0
fi

DNS="$ARG"
DIG=(dig +short +time=3 +tries=1)
[ -n "$DNS" ] && DIG+=("@$DNS")
echo "resolver: ${DNS:-system default}"

blocked() { local a; a=$("${DIG[@]}" "$1" 2>/dev/null | head -1); [ -z "$a" ] || [ "$a" = "0.0.0.0" ] || [ "$a" = "::" ]; }

FAIL=0
echo
echo "== should be BLOCKED =="
for d in tempmail.plus mailinator.com croxyproxy.rocks flirtify.com mirami.chat \
         chat.flirtify.com www.blockaway.net free.geonix.com api.mirami.chat; do
  if blocked "$d"; then printf '  \033[32mblocked\033[0m  %s\n' "$d"
  else printf '  \033[31mLEAKED \033[0m  %s -> %s\n' "$d" "$("${DIG[@]}" "$d" | head -1)"; FAIL=$((FAIL+1)); fi
done

echo
echo "== must still RESOLVE (blocking these breaks the machine) =="
for d in api.anthropic.com claude.ai github.com raw.githubusercontent.com \
         registry.npmjs.org pypi.org apple.com icloud.com login.microsoftonline.com \
         zoom.us slack.com google.com cloudflare.com; do
  if blocked "$d"; then printf '  \033[31mBLOCKED\033[0m  %s  <-- allowlist it now\n' "$d"; FAIL=$((FAIL+1))
  else printf '  \033[32mok     \033[0m  %s\n' "$d"; fi
done

echo
if [ "$FAIL" -eq 0 ]; then
  echo "Deployment healthy."
else
  echo "$FAIL problem(s). Fix with:  pihole allow <domain>   (takes effect immediately)"
  exit 1
fi
