# DNS plan: Blocky replaces Pi-hole

Decided 2026-09-17. Pi-hole on 192.168.1.101 gets replaced by Blocky, running as a
container on the docker VM next to Traefik. Two reasons: wildcard local domains, and
the whole config lives in this repo as one YAML file.

## Problem

LAN clients resolve `*.vulpe.dev` and `*.fyrmforge.dev` to the public IP
(109.148.70.232), so traffic leaves the house and hairpins back through the router.
Pi-hole's local DNS records page cannot do wildcards, so every subdomain would need
its own entry.

## Why Blocky

- One YAML file: ad lists, upstreams, and local domains. Blocky never rewrites it, so
  it stays in git like the rest of `stacks/`.
- `customDNS` entries cover subdomains automatically. One line per domain, not per host.
- AdGuard Home was the alternative. It has the UI and the wildcards, but it rewrites
  `AdGuardHome.yaml` itself whenever the UI is used, which fights with git.

## Layout

- New stack `stacks/dns/`, with `docker-compose.yml` and `config.yml`.
- Runs on the docker VM, same host as Traefik. No port clash: DNS is 53, Traefik is 80/443.
- Ports 53/udp and 53/tcp published on the host. Check nothing else holds 53 first
  (`ss -ulpn | grep :53`); `systemd-resolved` often does.
- Traefik route for the future admin UI goes in `stacks/traefik/dynamic/`, like every
  other service.

## Config sketch

```yaml
upstreams:
  groups:
    default:
      - https://dns.quad9.net/dns-query

bootstrapDns:
  - upstream: 1.1.1.1

customDNS:
  customTTL: 1m
  mapping:
    vulpe.dev: <TRAEFIK_LAN_IP>
    fyrmforge.dev: <TRAEFIK_LAN_IP>

blocking:
  denylists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  clientGroupsBlock:
    default:
      - ads

ports:
  dns: 53
  http: 4000
```

`<TRAEFIK_LAN_IP>` is still to be filled in. It is not recorded anywhere in this repo.

## Gotchas

- **The host must not use Blocky for DNS.** Docker image pulls go through the host
  resolver. If the host points at Blocky and Blocky is down for an update, the new
  image cannot be pulled and it never comes back. Point the host at the router or
  1.1.1.1. `bootstrapDns` covers Blocky's own lookups, so it does not need the host.
- **Blast radius.** DNS now dies with the docker VM. Rebooting that box takes the LAN
  offline for everyone, not just the self-hosted services. This is the one argument for
  a separate VM; accepted for now.
- **No fallback DNS in DHCP.** If the router hands out a second DNS server, clients
  silently use it and skip both the ad blocking and the local overrides.
- **No pause button.** Disabling blocking is an API or CLI call
  (`blocky blocking disable --duration 5m`), not a click. A small custom UI can wrap it.
- **Query log needs setup.** Point Blocky at a database or log file and read it in the
  existing Grafana. Nothing browsable out of the box.

## Steps

1. Find and record the Traefik host's LAN IP.
2. Free port 53 on the docker VM.
3. Add `stacks/dns/`, bring it up, and test against it directly:
   `dig @<docker-vm-ip> test.fyrmforge.dev` should return the LAN IP, and a known ad
   domain should return 0.0.0.0.
4. Point one machine at it by hand and live on it for a day. Pi-hole stays up.
5. Switch the router's DHCP DNS to the docker VM, single entry, no secondary.
6. Retire Pi-hole on .101 and delete `stacks/traefik/dynamic/pihole.yml`.
