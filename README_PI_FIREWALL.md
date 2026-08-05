# Pi-hole + Raspberry Pi firewall (planned extension)

Extension of the setup in `README_PIHOLE_ROUTER.md`: a Raspberry Pi becomes
the router/firewall in front of the network, closing the DNS-bypass hole
(a device hand-configured with `1.1.1.1` currently sails past Pi-hole).
The Ubuntu laptop stays exactly what it is today — the Pi-hole at
`192.168.1.2` — and the Toob Linksys Velop is demoted to WiFi access point
plus switch.

**Status: planned.** Hardware not yet purchased; the config below is the
agreed design, untested until the Pi is on the desk.

## Why the router can't do this

The Toob-supplied routers (Sagemcom earlier, Linksys Velop now) expose only
inbound port forwarding and parental controls — no outbound/egress firewall
rules, so "block LAN → internet port 53" cannot be expressed on them. The
enforcement has to live in a box we control, sitting in the traffic path.

## Chosen design: three boxes

Deliberate decision (see git history of this discussion): the Pi is
**firewall only**; Pi-hole stays on the laptop. Consolidating both onto the
Pi was offered and declined — the user prefers separate roles, accepting
router + firewall + Pi-hole as three points of failure.

```
Fiber ONT ──> Pi eth0 (WAN, DHCP from Toob, CGNAT)
              Pi = NAT + firewall + DHCP        ← new box
              Pi USB3 NIC (LAN, takes over 192.168.1.1)
                 │
              Velop in bridge mode ──> WiFi + LAN ports as switch
                 │
              laptop 192.168.1.2 = Pi-hole (unchanged)
```

Key trick: the Pi claims `192.168.1.1` (today the Velop's address), so every
device's existing gateway setting — including the laptop's static config in
`README_PIHOLE_ROUTER.md` — keeps working without reconfiguration. The Pi's
DHCP hands out the same pool (`.100`–`.249`), gateway = itself,
DNS = `192.168.1.2`, exactly what the Velop advertises today.

## Hardware

- Raspberry Pi 4 (fine up to ~500 Mbps tiers) or Pi 5 (for 900 Mbps) —
  older Pis are out: their Ethernet hangs off a USB 2 bus
- Official PSU
- USB 3 gigabit Ethernet adapter (e.g. TP-Link UE300, RTL8153 — well
  supported by the Linux kernel) as the second NIC
- A2-class SD card, plus a **second SD card** flashed with the finished
  image as the drawer spare — this box can take the whole house down

## Firewall rules (nftables, to be written when hardware arrives)

1. Masquerade LAN → WAN (standard NAT).
2. **DNAT any LAN port-53 traffic not from `192.168.1.2` to
   `192.168.1.2`** — a device using 1.1.1.1 silently gets Pi-hole's
   answers instead. Needs an accompanying SNAT: Pi-hole lives on a
   different box than the firewall, so without it the laptop would reply
   directly to the client from an unexpected address and the client would
   drop the response. Side effect: bypass queries log in Pi-hole as coming
   from the Pi, not the guilty device; normal DHCP-configured queries still
   go straight to the laptop and log per-device.
3. Allow outbound 53 from `192.168.1.2` (Pi-hole's own upstreams).
4. Drop outbound 853 (DoT — Android "Private DNS" etc.).

Hostname-based DoH is already covered by the hagezi DoH/VPN/proxy-bypass
adlist on the Pi-hole. Known ceiling: DoH straight to a hardcoded IP
(`https://1.1.1.1/dns-query`) still gets through — accepted.

## Verification (the money shot)

From any LAN device, after cutover:

```
dig +short example.com @1.1.1.1        # must answer with Pi-hole's view
dig +short flirtify.com @1.1.1.1       # must return the sinkhole, not a real IP
dig +short example.com @192.168.1.2    # normal path still works
```

If `@1.1.1.1` returns Cloudflare's real answers, the redirect isn't working.

## Remaining work when the Pi arrives

- [ ] Flash OS, static IPs on both NICs (`eth0` WAN, USB NIC `192.168.1.1`)
- [ ] nftables config implementing the four rules above
- [ ] DHCP server on the Pi (pool `.100`–`.249`, DNS `192.168.1.2`)
- [ ] Velop into bridge mode (its DHCP off, new IP out of the pool)
- [ ] Run the verification digs; then `make check DNS=192.168.1.2`
- [ ] Flash the spare SD card from the working image
