# Pi-hole Blocklists

DNS blocklists for Pi-hole:

- **`temp-email-sites.txt`** — websites of temporary/disposable email services (temp mail, 10 minute mail, fake mail generators, edu mail generators)
- **`free-proxy-sites.txt`** — free web proxies / site unblockers (CroxyProxy and friends) and free proxy-list providers (Webshare, Geonode, ProxyScrape…)

## Usage

Add the raw URL of each list as an adlist in Pi-hole
(**Admin → Lists** in v6, **Group Management → Adlists** in v5), then update gravity:

```
pihole -g
```

## Scope

These lists block the service **frontends** people visit. They complement — do not replace — the bigger maintained lists:

- https://github.com/disposable-email-domains/disposable-email-domains (disposable email domains)
- https://github.com/7c/fakefilter (disposable email domains, larger)
- https://github.com/hagezi/dns-blocklists (`doh-vpn-proxy-bypass` — DoH resolvers, VPN and proxy endpoints)

Use them together.

The commented-out "aggressive" section at the bottom of the list contains domains that also break legitimate products (Internxt, AdGuard, alias services). Uncomment at your own risk.

## Contributing

One bare domain per line, sorted, no `http://`, no paths. PRs welcome.
