#!/usr/bin/env bash
# Apply this repo's blocklists to a single Mac -- no Pi-hole needed.
#
#   bash macblock.sh status         what is currently active
#   sudo bash macblock.sh hosts-on  block the domains via /etc/hosts
#   sudo bash macblock.sh hosts-off remove them
#   sudo bash macblock.sh pf-on     block the IPs via the pf firewall
#   sudo bash macblock.sh pf-off    remove them
#   python3 refresh-ips.py          refresh the IP list from the internet
#
# hosts-on/off are idempotent: they replace one marked block, never append.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MARK_BEGIN="# BEGIN pihole-blocklists"
MARK_END="# END pihole-blocklists"
PF_TABLE="proxyblock"
# Installed OUTSIDE the clone: /etc/pf.conf keeps an include pointing here, and a
# dangling include makes pf load NOTHING at boot (Apple's anchors included).
PF_CONF="/etc/pf.anchors/pihole-blocklists.pf.conf"
PF_IPS="/etc/pf.anchors/pihole-blocklists.ips"

need_root() { [ "$(id -u)" = 0 ] || { echo "run with: sudo bash $0 $1"; exit 1; }; }
strip() { grep -hv '^[[:space:]]*#' "$@" 2>/dev/null | grep -v '^[[:space:]]*$'; }

# /etc/hosts has NO wildcards -- it matches exact hostnames only. That is exactly
# what expanded/ is for; the bare *-sites.txt would miss every www. subdomain.
hosts_source() {
  if compgen -G "$REPO/expanded/*-expanded.txt" >/dev/null; then
    # proxy-listicles is opt-in: set INCLUDE_LISTICLES=1 to pull it in too
    if [ "${INCLUDE_LISTICLES:-0}" = 1 ]; then
      strip "$REPO"/expanded/*-expanded.txt
    else
      strip $(ls "$REPO"/expanded/*-expanded.txt | grep -v listicles)
    fi
  else
    echo "no expanded/ lists found -- run: make build" >&2; exit 1
  fi
  # upstream layer (hagezi, ~90k hostnames) -- local-mac only; fetch with:
  # make refresh-upstream. Pi-hole users subscribe to hagezi as an adlist instead.
  if [ -f "$HERE/upstream-hosts.txt" ]; then
    strip "$HERE/upstream-hosts.txt"
  fi
}

case "${1:-}" in

status)
  echo "== /etc/hosts =="
  n=$(grep -c '^0\.0\.0\.0' /etc/hosts 2>/dev/null || echo 0)
  if grep -q "$MARK_BEGIN" /etc/hosts 2>/dev/null; then
    echo "  ACTIVE (this repo) - $n domains blocked"
  elif [ "$n" -gt 0 ]; then
    echo "  $n domains blocked, but NOT by this repo's marker."
    echo "  Another tool wrote them (e.g. an older ~/proxy-lists install)."
    echo "  'hosts-on' adds this repo's block alongside them and leaves them alone."
  else
    echo "  not installed"
  fi
  echo "== pf =="
  if pfctl -s info 2>/dev/null | grep -q 'Status: Enabled'; then
    n=$(pfctl -t "$PF_TABLE" -T show 2>/dev/null | wc -l | tr -d ' ')
    echo "  pf ENABLED, table <$PF_TABLE> has ${n:-0} IPs"
  else
    echo "  pf disabled"
  fi
  echo "== quick resolution test =="
  for d in api.anthropic.com github.com tempmail.plus flirtify.com; do
    a=$(dscacheutil -q host -a name "$d" 2>/dev/null | awk '/ip_address/{print $2; exit}')
    printf '  %-22s %s\n' "$d" "${a:-<no answer>}"
  done
  ;;

hosts-on)
  need_root hosts-on
  STAMP=$(date +%Y%m%d-%H%M%S)
  cp /etc/hosts "/etc/hosts.bak.$STAMP"
  echo "backup: /etc/hosts.bak.$STAMP"
  TMP=$(mktemp)
  # replace only our marked block; entries written by other tools are left alone
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0,b)==1 {skip=1; next}
    index($0,e)==1 {skip=0; next}
    skip {next}
    1' /etc/hosts > "$TMP"
  BLOCK=$(mktemp)
  hosts_source | sort -u > "$BLOCK"
  # Belt on top of the generators' own filtering: never block a critical host.
  if grep -qxE 'api\.anthropic\.com|claude\.ai|github\.com|apple\.com|icloud\.com' "$BLOCK"; then
    echo "ABORT: a critical host is in the block list -- refusing to write /etc/hosts"
    rm -f "$TMP" "$BLOCK"; exit 1
  fi
  {
    echo "$MARK_BEGIN (generated $STAMP - edit the repo lists, not this block)"
    sed 's/^/0.0.0.0 /' "$BLOCK"
    echo "$MARK_END"
  } >> "$TMP"
  cat "$TMP" > /etc/hosts    # cat not mv: preserves owner and permissions
  rm -f "$TMP" "$BLOCK"
  dscacheutil -flushcache; killall -HUP mDNSResponder
  echo "/etc/hosts: $(grep -c '^0\.0\.0\.0' /etc/hosts) domains blocked"
  if [ ! -f "$HERE/upstream-hosts.txt" ]; then
    echo "tip: 'make refresh-upstream' adds hagezi's ~90k VPN/proxy/DoH hostnames to this block"
  fi
  ;;

hosts-off)
  need_root hosts-off
  cp /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d-%H%M%S)"
  TMP=$(mktemp)
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0,b)==1 {skip=1; next}
    index($0,e)==1 {skip=0; next}
    skip {next}
    1' /etc/hosts > "$TMP"
  cat "$TMP" > /etc/hosts; rm -f "$TMP"
  dscacheutil -flushcache; killall -HUP mDNSResponder
  echo "removed. /etc/hosts now has $(grep -c '^0\.0\.0\.0' /etc/hosts || echo 0) blocked domains"
  ;;

pf-on)
  need_root pf-on
  IPS="$REPO/firewall/proxy-ips.txt"
  [ -s "$IPS" ] || { echo "missing $IPS -- run: python3 $HERE/refresh-ips.py"; exit 1; }

  # Refuse to load a list that would cut this machine off from anything critical.
  for h in api.anthropic.com github.com; do
    for ip in $(dig +short "$h" | grep -E '^[0-9]+\.'); do
      grep -qxF "$ip" "$IPS" && {
        echo "ABORT: $h ($ip) is in the block list."
        echo "       Add its prefix to local-mac/ip-allowlist.txt and re-run refresh-ips.py"
        exit 1; }
    done
  done

  grep -v '^[[:space:]]*#' "$IPS" | grep -v '^[[:space:]]*$' > "$PF_IPS"
  [ -s "$PF_IPS" ] || { echo "ABORT: $IPS contains no IPs (headers only) -- run refresh-ips.py"; rm -f "$PF_IPS"; exit 1; }
  cat > "$PF_CONF" <<EOF
table <$PF_TABLE> persist file "$PF_IPS"
block drop out quick to <$PF_TABLE>
EOF
  # Append to /etc/pf.conf, never replace it: flushing the main ruleset removes
  # Apple's anchors and can break VPN clients and Internet Sharing.
  # Build a candidate and syntax-check it BEFORE touching the real file.
  cp /etc/pf.conf "/etc/pf.conf.bak.$(date +%Y%m%d-%H%M%S)"
  TMP=$(mktemp)
  grep -v 'pihole-blocklists' /etc/pf.conf | grep -v 'proxy-block\.pf\.conf' > "$TMP"
  printf '\n# pihole-blocklists (local-mac)\ninclude "%s"\n' "$PF_CONF" >> "$TMP"
  pfctl -n -f "$TMP" || { echo "ABORT: candidate pf.conf failed syntax check; /etc/pf.conf untouched"; rm -f "$TMP"; exit 1; }
  cat "$TMP" > /etc/pf.conf; rm -f "$TMP"
  pfctl -f /etc/pf.conf
  pfctl -E 2>/dev/null || true
  echo "pf table <$PF_TABLE>: $(pfctl -t $PF_TABLE -T show | wc -l | tr -d ' ') IPs"
  echo "NOTE: pf resets on reboot. See local-mac/README.md for the LaunchDaemon."
  ;;

pf-off)
  need_root pf-off
  cp /etc/pf.conf "/etc/pf.conf.bak.$(date +%Y%m%d-%H%M%S)"
  TMP=$(mktemp)
  # also drops the pre-anchor include (".../proxy-block.pf.conf") from old installs
  grep -v 'pihole-blocklists' /etc/pf.conf | grep -v 'proxy-block\.pf\.conf' > "$TMP"
  cat "$TMP" > /etc/pf.conf; rm -f "$TMP"
  rm -f "$PF_CONF" "$PF_IPS"
  pfctl -t "$PF_TABLE" -T flush 2>/dev/null || true
  pfctl -f /etc/pf.conf
  echo "pf rules removed (pf itself left enabled; 'sudo pfctl -X' to disable)"
  ;;

*)
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
