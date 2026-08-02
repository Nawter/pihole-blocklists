# Pi-hole network setup (Ubuntu Server laptop + router)

Network-wide ad blocking with Pi-hole running on an Ubuntu Server laptop, connected to the
router via a USB-to-Ethernet adapter, without sacrificing internet speed.

## Background: why the laptop must NOT sit inline

Originally the laptop was wired *between* the fiber modem and the WiFi router:

```
WRONG (bottleneck):
Fiber modem ──> Laptop (USB adapter, 100 Mbps) ──> WiFi router ──> Devices
                        └── all traffic squeezed through here: 716 → 89 Mbps
```

Every byte of traffic for the whole house was forced through the laptop's USB Ethernet
adapter, which only supports 100 Mbps (real-world ~89 Mbps).

Pi-hole is DNS-only. It never needs to sit in the traffic path — it just needs to be
*reachable* on the network. Correct topology:

```
CORRECT:
Fiber modem ──> WiFi router (WAN port) ──> Devices (full speed)
                     │ (LAN port)
                     └──> Pi-hole laptop (DNS queries only)
```

Only tiny DNS lookups cross the slow USB adapter, so its 100 Mbps limit no longer matters.

## Step 1 — Re-cable

1. Unplug the blue cable (from the fiber modem) from the laptop and plug it directly into
   the router's **WAN/Internet port** (usually a differently-colored port).
2. Plug the black cable (still attached to the laptop's USB adapter) into one of the
   router's **LAN ports**.
3. Reboot the router and confirm the internet works on a phone. Full speed should already
   be restored at this point.

## Step 2 — Undo old config on the laptop

If internet sharing, NAT, or bridging was configured on the laptop for the old inline
setup, disable it. The laptop is now just a normal client on the network.

## Step 3 — Static IP on the laptop (Ubuntu Server → Netplan)

Ubuntu Server uses Netplan, not NetworkManager, so `nmcli` is not available.

The router's DHCP pool is `192.168.1.100`–`192.168.1.249`, so anything in
`192.168.1.2`–`192.168.1.99` is safe as a static IP. This setup uses **192.168.1.2**.

### 3.1 Find the interface name (the USB adapter)

```bash
ip a
```

USB adapters usually show up as `enx<MAC>` (e.g. `enx00e04c680001`) or `eth0`/`enp0s...`.
Note the exact name.

### 3.2 Edit the netplan config

```bash
ls /etc/netplan/
sudo nano /etc/netplan/00-installer-config.yaml   # or whatever .yaml file exists
```

Make it look like this, replacing `enx00e04c680001` with the actual interface name
(YAML: indentation matters, spaces only, no tabs):

```yaml
network:
  version: 2
  ethernets:
    enx00e04c680001:
      dhcp4: no
      addresses:
        - 192.168.1.2/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 127.0.0.1
```

- `192.168.1.2/24` — static IP + subnet mask in one
- `via: 192.168.1.1` — gateway (the router)
- `127.0.0.1` — the laptop uses its own Pi-hole for DNS

### 3.3 Apply

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try
```

`netplan try` auto-rolls-back after 120 seconds unless confirmed with Enter — a lifesaver
on a headless box, since a typo won't lock you out. Press Enter if the connection survives.
(`sudo netplan apply` also works, but `try` is safer.)

### 3.4 Verify

```bash
ip a                 # should show 192.168.1.2 on the adapter
ip route             # default via 192.168.1.1
ping -c 3 8.8.8.8    # internet works
ping -c 3 google.com # DNS resolution through Pi-hole works
```

### Gotchas

- **cloud-init overwrites**: if the config file is `50-cloud-init.yaml`, cloud-init may
  overwrite edits on reboot. Prevent it with:

  ```bash
  echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  ```

- **Interface renaming**: USB adapters occasionally get renamed after a reboot or when
  plugged into a different USB port. If the network dies after a reboot, run `ip a` and
  check that the name in the yaml still matches.

## Step 4 — Router settings (the key part)

In the router admin (`http://192.168.1.1` → LAN Settings → **DHCP Server** tab):

- **DHCP Server toggle**: leave **ON** (the router hands out addresses, not Pi-hole).
- **Static DNS 1**: `192.168.1.2` (the Pi-hole laptop).
- **Static DNS 2**: leave **blank**. If the router refuses to save with it empty, enter
  `192.168.1.2` again. Never put a public DNS (e.g. `8.8.8.8`) here — devices would use
  it to bypass Pi-hole.
- **Gateway**: this router has no gateway field on the DHCP page — it always hands out
  itself (`192.168.1.1`) as the gateway, which is exactly what we want. If a gateway
  field exists on your router, it must point at the router, never the laptop.

Save/apply.

## Step 5 — Pi-hole settings

In the Pi-hole admin (`http://192.168.1.2/admin`):

1. **Disable Pi-hole's DHCP server** (Settings → DHCP) if it was enabled for the old
   setup. Two DHCP servers on one network causes chaos; the router handles DHCP now.
2. **Interface/listening** (Settings → DNS → Interface settings): select
   **"Permit all origins"** (or "Respond only on interface X" pointing at the USB
   adapter). Queries now arrive from the router's LAN, not a direct cable.
3. **Upstream DNS** (same page): make sure an upstream resolver is ticked (Cloudflare,
   Quad9, Google, ...). This is where Pi-hole forwards queries it doesn't block.

Then restart DNS:

```bash
pihole restartdns
```

Reset the web admin password if needed:

```bash
sudo pihole setpassword     # v6+; blank password twice = no login required
sudo pihole -a -p           # older v5.x syntax
```

## Step 6 — Reconnect devices & verify

1. Toggle WiFi off/on on each device (or wait for DHCP lease renewal) so it picks up the
   new DNS.
2. **Speed test**: should show full line speed (~716 Mbps), since only DNS queries touch
   the laptop.
3. **Ad blocking**: visit an ad-heavy site — ads should be blocked.
4. **Pi-hole dashboard**: should show queries flowing in from device IPs
   (`192.168.1.100+`).

Useful checks from any device:

- Gateway must be the router (`192.168.1.1`) and DNS must be the laptop (`192.168.1.2`).
  On Windows: `ipconfig /all`. If the *gateway* shows the laptop's IP, traffic is being
  routed through the laptop again — wrong.
- `tracert 8.8.8.8` / `traceroute 8.8.8.8`: first hop must be `192.168.1.1`, not the
  laptop.

## Note on subnets

If the router uses a different range than `192.168.1.x` (e.g. `192.168.0.x`), adjust the
laptop's static IP, the netplan gateway, and the router's Static DNS entry to match the
router's actual range.