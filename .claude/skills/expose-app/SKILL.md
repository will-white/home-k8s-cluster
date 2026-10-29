---
name: expose-app
description: >-
  Expose an app over HTTPS through the Cilium Gateways (internal LAN-only or
  external via Cloudflare), or give it a routed LoadBalancer IP, with DNS,
  TLS, network policy and Gatus wired the way this repo does it. Use when the
  user asks to "expose", "publish", "make reachable", "add a hostname",
  "put behind the gateway", "make public" or "give it an IP".
---

# Expose an app

Reference: `docs/network-layout.md`, `kubernetes/apps/network/CLAUDE.md`.
There are no Ingress objects and no per-app DNS records: a route is the whole
contract.

## HTTP(S): a route on a Gateway

app-template HelmRelease:

```yaml
route:
  app:
    hostnames: ["{{ .Release.Name }}.${SECRET_DOMAIN}"]   # or an explicit name
    parentRefs:
      - name: internal          # external = public (see below)
        namespace: network
        sectionName: https
    rules:
      - backendRefs:
          - identifier: app
            port: http
        timeouts:
          request: 0s           # Envoy defaults to 15 s; nginx had none
```

Charts without `route:` support get a raw `HTTPRoute` in `app/` with the same
`parentRefs` (example: `kubernetes/apps/flux-system/headlamp/app/httproute.yaml`).

What happens on merge: `adguard-dns-internal` creates the LAN record pointing
at `192.168.110.46`; TLS is the Gateway's wildcard certificate; the
`allow-from-ingress` template (already in every default-deny namespace) admits
Envoy. Add Homepage `gethomepage.dev/*` annotations on the route if the app
belongs on the dashboard, and `../../../../templates/gatus/guarded` in the
kustomization for a health check.

### Making it public

Change `parentRefs[0].name` to `external`. That alone publishes a proxied
Cloudflare CNAME (`cloudflare-dns`) and a LAN override to `192.168.110.48`
(`adguard-dns-external`); the tunnel forwards to the external Gateway. Before
doing it, say in the PR: what auth the app has (there is no SSO yet; see
`docs/backlog.md`), and switch the Gatus template to `gatus/external`. This is
a security decision for the user, not a default.

### Checks

```bash
task kubernetes:validate APP=<ns>/<app>
# after merge (needs KUBECONFIG):
kubectl -n <ns> get httproute <app> -o yaml | yq .status      # Accepted + ResolvedRefs True
kubectl -n network logs deploy/adguard-dns-internal | tail       # record created
```

## Non-HTTP: a LoadBalancer IP

Only for protocols the Gateway cannot carry (MQTT, RTSP/WebRTC, Postgres,
tdarr). Routed via BGP by default:

1. Add `<NAME>_LB: 192.168.110.<next free>` to
   `kubernetes/flux/vars/cluster-settings.yaml` (allocations in
   `docs/network-layout.md`).
2. On the Service (app-template `service.<name>`):

   ```yaml
   type: LoadBalancer
   labels:
     lb-pool: bgp
   annotations:
     lbipam.cilium.io/ips: ${<NAME>_LB}
   ```

3. If LAN devices must reach it, the namespace needs `allow-ingress-lan` (or
   a scoped policy next to the HelmRelease).

Use the L2 pool (`192.168.5.x`, no label) only when off-cluster devices
hard-code the IP and cannot be re-pointed (UniFi today). Never advertise the
LAN /24 over BGP.
