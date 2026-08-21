---
title: TLS and mTLS
description: Serve HTTPS from the pod instead of terminating at the edge, rotate the certificate without a restart, and require client certificates.
weight: 6
translationKey: helm-chart-tls
---

By default the pod serves plain HTTP and something in front of it terminates TLS: the Ingress controller through `ingress.tls`, or the Gateway listener an HTTPRoute attaches to. That model is the simpler one and it is what most deployments should keep. See [Networking]({{< relref "networking" >}}) for both routes.

The `tls` block covers the deployments where that is not enough:

- the hop between the proxy and the pod must be encrypted too, because a mesh re-encrypts backend traffic, because a Gateway API `BackendTLSPolicy` requires it, or because a control mandates encryption in transit everywhere
- nothing fronts the Service, so the pod is the TLS endpoint
- clients must prove who they are with a certificate, not only with an OIDC token

## Prerequisites

A server image that supports the `server.tls` configuration section. A server that does not know the section ignores it and keeps serving plain HTTP, while the chart has already pointed the probes at HTTPS, so the pods fail readiness and the release never finishes rolling. Check [Compatibility]({{< relref "/integrations/compatibility" >}}) before enabling.

A certificate and key in a Secret you own. The chart never generates certificates. A `kubernetes.io/tls` Secret from cert-manager, from an internal PKI, or from `kubectl create secret tls` works as it is, because `tls.certKey` and `tls.keyKey` already default to `tls.crt` and `tls.key`. A self-signed certificate is a local testing tool: it forces every client to trust a CA created for one workload, which is the opposite of what a certificate is for.

## Serve HTTPS from the pod

```yaml
tls:
  enabled: true
  existingSecret: github-sts-tls
  reloadInterval: "1h"
```

The chart refuses to render `tls.enabled: true` without `tls.existingSecret`, rather than starting a pod that has no certificate to serve.

Enabling TLS changes six things:

| What | Change |
|---|---|
| Certificate material | Projected read-only at `tls.mountPath`, default `/etc/github-sts-tls`, and written into the ConfigMap as `server.tls.cert_file` and `server.tls.key_file`. |
| Container and Service port | Named `https` instead of `http`, and the Service port gains `appProtocol: https`. Mesh implementations and some ingress controllers read the port name to decide how to speak to the backend. |
| Probes | `httpGet` with `scheme: HTTPS`. The kubelet does not verify the certificate on a probe, so a certificate valid only for the public hostname still passes. |
| Prometheus scrapes | ServiceMonitor and PodMonitor endpoints get `scheme: https`. |
| `helm test` hooks | Fetch over HTTPS without verifying the certificate. |
| The proxy in front | Nothing. Ingress and Gateway keep sending plain HTTP until you configure them, which is the next section. |

The mount path sits beside `/etc/github-sts` rather than inside it. The ConfigMap is mounted read-only at `/etc/github-sts`, and a container runtime cannot create a mount point inside a read-only mount, so a nested path fails at container creation with a read-only filesystem error. Override `tls.mountPath` if you like, but keep it out of `/etc/github-sts`.

### Rotate without a restart

`tls.reloadInterval` is a Go duration, and the server polls the mounted files on that interval and reloads the key pair in place when either changes. Leave it empty and the process keeps the certificate it read at startup, so a renewal only takes effect the next time the pod restarts.

Kubernetes refreshes a mounted Secret in place, so nothing else has to happen for the new file to appear in the pod. Pick an interval well under the renewal window. cert-manager renews at two thirds of the certificate lifetime by default, so an hourly poll is comfortable for a 90 day certificate and still fast enough for a short-lived one.

## Tell the proxy to speak HTTPS

Turning on `tls` does not reconfigure the thing in front of the Service, and the backend protocol is controller-specific.

For ingress-nginx:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
```

For Gateway API, add a `BackendTLSPolicy` next to the release. The chart does not render one, because the API version tracks the Gateway API installation in your cluster rather than the chart:

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata:
  name: github-sts
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: github-sts
      sectionName: https
  validation:
    caCertificateRefs:
      - group: ""
        kind: Secret
        name: github-sts-tls
    hostname: sts.example.com
```

A proxy that still sends plain HTTP to an HTTPS listener returns a gateway error to every client, and the pods stay healthy while it happens, so the failure looks like a routing problem rather than a TLS one.

## Require client certificates

```yaml
tls:
  enabled: true
  existingSecret: github-sts-tls
  clientAuth:
    enabled: true
    existingSecret: github-sts-client-ca
    caKey: ca.crt
```

Leave `clientAuth.existingSecret` empty and the CA bundle is read from `tls.existingSecret`, which is where cert-manager writes `ca.crt` next to the serving certificate.

The server requires and verifies a client certificate for the whole listener. `/health`, `/ready`, and `/metrics` are not exceptions, so every caller that cannot present a certificate loses access at the handshake. The chart adjusts what it controls:

| Caller | What the chart does |
|---|---|
| kubelet probes | Switches startup, readiness, and liveness to `tcpSocket`. The kubelet cannot present a client certificate, and an HTTPS probe against this listener would fail the handshake and restart the container in a loop. |
| `helm test` hooks | Stops rendering them. The hook Pods have no certificate, so every assertion would fail at the handshake. |
| Prometheus | Nothing automatic. Put the client credentials in `serviceMonitor.tlsConfig` or `podMonitor.tlsConfig`, or scrapes fail. |

The probe change is a real loss of signal. A `tcpSocket` probe proves the listener accepts connections, not that `/ready` returns 200, so a server that is up but not ready stays in the Service endpoints. Readiness gating for anything richer than that has to come from a caller that holds a certificate. `probes.mode: httpGet` forces the HTTP probes back, and is correct only when something else terminates mTLS before the container.

## Scrape metrics over TLS

With `tls.enabled` and no explicit configuration, the chart writes `insecureSkipVerify: true` into the scrape endpoint. Prometheus connects to the Pod IP, and a certificate issued for the Service or the public hostname carries no SAN for it, so verification would fail on every scrape. The scrape is encrypted, the target is not authenticated.

Verify the target properly by naming the CA and the hostname the certificate was issued for:

```yaml
serviceMonitor:
  enabled: true
  tlsConfig:
    ca:
      secret:
        name: github-sts-tls
        key: ca.crt
    serverName: sts.example.com
```

Under `clientAuth`, add the client credentials Prometheus should present:

```yaml
serviceMonitor:
  tlsConfig:
    cert:
      secret:
        name: prometheus-client-cert
        key: tls.crt
    keySecret:
      name: prometheus-client-cert
      key: tls.key
```

`podMonitor.tlsConfig` takes the same shape. Setting either replaces the default, so `insecureSkipVerify` is gone as soon as you supply your own block.

## Choose a version and cipher suites

`tls.minVersion` accepts `"1.2"`, the default, and `"1.3"`. TLS 1.3 removes cipher negotiation entirely and rejects clients that cannot speak it, which includes the BusyBox image the `helm test` hooks run by default.

`tls.cipherSuites` is an allow-list of IANA names for TLS 1.2 only. Leave it empty and the server uses the Go defaults, which are already AEAD-only. Setting it together with `minVersion: "1.3"` is a configuration error the server rejects at startup, so the chart fails the render instead:

```yaml
tls:
  minVersion: "1.2"
  cipherSuites:
    - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
    - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

## Verify

Read what the chart wrote before applying it:

```bash
helm template github-sts charts/github-sts --values values.yaml \
  --show-only templates/configmap.yaml
```

Confirm the probes match the listener:

```bash
kubectl get deployment github-sts --namespace github-sts \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'
```

`httpGet` with `"scheme":"HTTPS"` is the TLS case, `tcpSocket` is the mTLS case, and plain `httpGet` means `tls.enabled` never took effect.

Confirm the endpoint answers over TLS from inside the cluster:

```bash
kubectl run tls-check --rm -i --restart=Never --namespace github-sts \
  --image=curlimages/curl:8.11.1 -- -sS -k https://github-sts:8080/health
```

`-k` skips verification, so this proves TLS is being served, not that the certificate is the one you meant to serve. To check the certificate itself, forward the port and read the chain:

```bash
kubectl port-forward --namespace github-sts svc/github-sts 8443:8080
openssl s_client -connect localhost:8443 -showcerts </dev/null
```

Under `clientAuth`, the same command fails the handshake until it presents a certificate:

```bash
openssl s_client -connect localhost:8443 -cert client.crt -key client.key </dev/null
```

Finish with the chart's own hooks, which follow the scheme automatically:

```bash
helm test github-sts --namespace github-sts
```

## Known limitations

- Under `clientAuth`, probes only prove the port accepts connections, and `helm test` is unavailable.
- The `helm test` hooks run BusyBox, whose `wget` speaks TLS 1.2 only. With `minVersion: "1.3"`, point `tests.image` at a curl image such as `curlimages/curl:8.11.1`. The hook script prefers `curl` when the image provides it and falls back to `wget`.
- `tls.mountPath` cannot be a subdirectory of `/etc/github-sts`.
- The chart mounts certificates and never creates them. Renewal belongs to cert-manager or your PKI.
- Prometheus does not verify the target unless you configure `tlsConfig` yourself.

## Next

- [Values Reference]({{< relref "values" >}}) for every `tls` value and its default
- [Rendered Resources]({{< relref "resources" >}}) for the mounts and ports these values change
- [Networking]({{< relref "networking" >}}) for the route in front of the Service
- [Security Model]({{< relref "/concepts/security-model" >}}) for what the server authenticates on top of the transport
