---
title: Networking
description: Expose the exchange endpoint with Ingress or HTTPRoute, and restrict what the pods may reach with either NetworkPolicy family.
weight: 5
translationKey: helm-chart-networking
---

A default install renders a `ClusterIP` Service and nothing else. Clients outside the cluster reach the exchange endpoint only once you enable a route, and the pods can reach any destination until you enable a policy.

## Expose the endpoint

Enable exactly one of `ingress` and `httproute`. Both forward to the same Service, and running both leaves two independent paths to the same endpoint with two independent TLS configurations.

### Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: sts.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: github-sts-tls
      hosts:
        - sts.example.com
```

The `hosts` default carries the placeholder `github-sts.example.com`. Replace it: enabling `ingress` without editing `hosts` publishes a route for a hostname you do not own.

Configure TLS. Clients send the OIDC token as a bearer credential in the `Authorization` header, so an Ingress with no `tls` block puts a signed identity assertion on the wire in plaintext, where it can be captured and replayed until it expires.

### HTTPRoute

The Gateway API alternative. Requires the Gateway API CRDs and an existing Gateway; TLS terminates on the Gateway listener rather than in this chart.

```yaml
httproute:
  enabled: true
  parentRefs:
    - name: external
      namespace: gateway-system
      sectionName: https
  hostnames:
    - sts.example.com
  port: 8080
```

The rendered route matches the path prefix `/` and forwards to the Service on `httproute.port`. `parentRefs` entries accept `name`, and optionally `kind`, `group`, `namespace`, and `sectionName`.

## Restrict traffic

The chart ships two NetworkPolicy templates and enables neither. Pick the one your CNI implements; enabling both is a reasonable defense-in-depth choice on a Cilium cluster that also honors the upstream API.

Both are scoped to this chart's pods, and both are shaped the same way:

- **Ingress:** who may reach the Service port. Leave the peer list empty and no in-cluster traffic is admitted.
- **Egress:** DNS, plus TCP 443 to the destinations you allow.

The server needs egress to the GitHub API, and to the JWKS endpoint of every issuer in `oidc.allowedIssuers`. Miss either and exchanges fail with a connection error rather than a policy denial, which is much harder to read in an incident.

A `bundles` entry adds a third destination: the host its `ref` points at. Nothing in the chart derives that host, so add it to `fqdns` on the Cilium side or to `cidrs` on the native side. How the server reacts to a bundle it cannot fetch is set by `fail_mode` on the entry rather than by the policy.

### Native NetworkPolicy

Works on any CNI implementing `networking.k8s.io/v1`. That API cannot match a destination by hostname, so external destinations are CIDR ranges you maintain.

```yaml
networkPolicy:
  allowKubeDns: true
  native:
    enabled: true
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    cidrs:
      - 140.82.112.0/20
      - 192.30.252.0/22
```

The rendered policy sets `policyTypes: [Ingress, Egress]`, so anything not listed is denied. `cidrs` opens TCP 443 only.

GitHub publishes its ranges at [`https://api.github.com/meta`](https://api.github.com/meta), and they change. Pin a review of that list to your upgrade routine, because a range that drops out of your allow-list surfaces as intermittent exchange failures.

### CiliumNetworkPolicy

Requires the Cilium CRD, and matches egress by hostname, which removes the CIDR maintenance.

```yaml
networkPolicy:
  allowKubeDns: true
  cilium:
    enabled: true
    fromEndpoints:
      - matchLabels:
          io.kubernetes.pod.namespace: ingress-nginx
    fqdns:
      - matchName: api.github.com
```

`deriveJwksHostsFromIssuers` is on by default. The chart appends the host of every `oidc.allowedIssuers` entry, and every host listed in `oidc.trustedJwksHosts`, to the FQDN allow-list as `matchName` entries. Adding an issuer therefore opens its key fetch automatically, and an issuer that serves JWKS from another host — `accounts.google.com` signing tokens whose keys live on `www.googleapis.com` — is covered as soon as you declare that in `oidc.trustedJwksHosts`.

Set `deriveJwksHostsFromIssuers: false` only if you intend to maintain `fqdns` by hand. The derived entries disappear with it.

### DNS

`networkPolicy.allowKubeDns` defaults to true and applies to whichever policy kinds are enabled. It permits UDP and TCP 53 to `kube-dns` in `kube-system`. Turning it off without providing your own DNS rule in `extraEgress` breaks every hostname lookup, including the FQDN rules above, which resolve names before they can match.

### Anything else

`extraIngress` and `extraEgress` are merged verbatim into the rendered policy, in the shape of the API you enabled. Use them for a Redis backend, an egress proxy, or a metrics scraper that is not covered by the peer lists.

```yaml
networkPolicy:
  native:
    extraEgress:
      - to:
          - podSelector:
              matchLabels:
                app.kubernetes.io/name: redis
        ports:
          - port: 6379
            protocol: TCP
```

## Verify

Render the policy and read it before applying:

```bash
helm template github-sts charts/github-sts --values values.yaml \
  --show-only templates/networkpolicy.yaml
```

Then confirm from inside a pod that the destinations you expect are the destinations that work:

```bash
kubectl exec --namespace github-sts deploy/github-sts -- \
  wget -qO- https://api.github.com/meta > /dev/null && echo reachable
```

A policy that denies in-cluster ingress also denies the chart's test Pods, so `helm test` starts failing. Add their namespace to the peer list if you want to keep running it.

## Next

- [Values Reference]({{< relref "values" >}}) for every routing and policy value
- [Rendered Resources]({{< relref "resources" >}}) for the objects these values produce
- [Troubleshooting]({{< relref "/operations/troubleshooting" >}}) for reading a failed exchange
