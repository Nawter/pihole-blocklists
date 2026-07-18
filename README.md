# Pi-hole Temp Email Sites Blocklist

Blocks the **websites** of temporary/disposable email services (temp mail, 10 minute mail, fake mail generators, edu mail generators) at the DNS level.

## Usage

Add the raw URL of `temp-email-sites.txt` as an adlist in Pi-hole
(**Admin → Lists** in v6, **Group Management → Adlists** in v5), then update gravity:

```
pihole -g
```

## Scope

This list blocks the service **frontends** people visit to get a throwaway inbox. It complements — does not replace — the lists that cover the disposable **email domains** themselves:

- https://github.com/disposable-email-domains/disposable-email-domains
- https://github.com/7c/fakefilter

Use all three together.

The commented-out "aggressive" section at the bottom of the list contains domains that also break legitimate products (Internxt, AdGuard, alias services). Uncomment at your own risk.

## Contributing

One bare domain per line, sorted, no `http://`, no paths. PRs welcome.
