# github-sts

A Kubernetes Helm chart for deploying [github-sts](https://github.com/Depthmark/github-sts) — a Python-based Security Token Service (STS) for the GitHub API.

Workloads with OIDC tokens (GitHub Actions, Azure, Google Cloud, etc.) exchange them for short-lived, scoped GitHub installation tokens. No PATs required. Supports multiple GitHub Apps with YAML-based configuration (ideal for Kubernetes ConfigMaps).

**Homepage:** <https://github.com/Depthmark/github-sts-helm>

## Source Code

* <https://github.com/Depthmark/github-sts-helm>
* <https://github.com/Depthmark/github-sts>

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- At least one [GitHub App](https://docs.github.com/en/apps) registered with the required permissions
- A Kubernetes Secret containing the GitHub App private key

## Installation

### From OCI Registry (recommended)

```bash
# Create a secret with your GitHub App private key
kubectl create secret generic my-github-app-credentials \
  --from-file=github-app-private-key=/path/to/private_key.pem

# Install the chart
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_GITHUB_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials"
```

### From Source

```bash
git clone https://github.com/Depthmark/github-sts-helm.git
cd github-sts-helm

kubectl create secret generic my-github-app-credentials \
  --from-file=github-app-private-key=/path/to/private_key.pem

helm install github-sts charts/github-sts \
  --set github.apps.default.appId="YOUR_GITHUB_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials"
```

### Multiple GitHub Apps

```bash
kubectl create secret generic app1-credentials \
  --from-file=github-app-private-key=/path/to/app1_key.pem
kubectl create secret generic app2-credentials \
  --from-file=github-app-private-key=/path/to/app2_key.pem

helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.app1.appId="111" \
  --set github.apps.app1.existingSecret="app1-credentials" \
  --set github.apps.app2.appId="222" \
  --set github.apps.app2.existingSecret="app2-credentials"
```

> **Note:** Each app's private key must be stored in an existing Kubernetes Secret.
> The app name is used in trust policy paths: `{policy.basePath}/{appName}/{identity}.sts.yaml`

## How It Works

```
  Workload                  github-sts                   GitHub
     │                          │                          │
     │  GET /sts/exchange       │                          │
     │  ?scope=org/repo         │                          │
     │  &app=my-app             │                          │
     │  &identity=ci            │                          │
     │  Authorization: Bearer   │                          │
     │─────────────────────────>│                          │
     │                          │  Validate OIDC sig/exp   │
     │                          │  Load trust policy       │
     │                          │  Evaluate claims         │
     │                          │  Request install token ──>
     │                          │<─────────────────────────│
     │<─────────────────────────│                          │
     │  { token, permissions }  │                          │
```

## Trust Policies

Policies are fetched directly from GitHub repositories at `{basePath}/{appName}/{identity}.sts.yaml`.

Default path: `.github/sts/{appName}/{identity}.sts.yaml`

Example policy (`.github/sts/default/ci.sts.yaml`):

```yaml
issuer: https://token.actions.githubusercontent.com
subject: repo:org/repo:ref:refs/heads/main
permissions:
  contents: read
  issues: write
```

See the [upstream documentation](https://github.com/Depthmark/github-sts#trust-policies) for full policy schema and examples.

## Enterprise Rego Bundles

Set `bundles` to configure signed OPA/Rego bundles. Bundles are evaluated after the YAML trust policy allows and before GitHub token minting, and a deny wins across all applicable bundles.

Bundle support is newer than the server release this chart's `appVersion` pins. Server v0.0.3 parses its config leniently: it ignores `bundles:`, starts, and serves exchanges with no Rego layer. Move `image.tag` or `image.digest` to a build with bundle support first.

A build that supports bundles also requires a top-level `bundle_enforcement` value (`required` or `optional`) and refuses to start without one. This chart does not render that key; supply it through `extraEnv`:

```yaml
extraEnv:
  - name: GITHUBSTS_BUNDLE_ENFORCEMENT
    value: required
```

```yaml
bundles:
  - name: enterprise-baseline
    apps: []
    ref: oci://ghcr.io/example/github-sts-policy@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    expected_policy_revision: "42"
    poll_interval: 5m
    max_staleness: 10m
    fail_mode: closed
    registry:
      auth:
        mode: basic
        username: robot$github-sts
        password_file: /var/run/secrets/bundle/registry-password
    cosign:
      certificate_identity_regexp: '^https://github\.com/example/github-sts-policy/\.github/workflows/release\.yml@refs/heads/main$'
      certificate_oidc_issuer: https://token.actions.githubusercontent.com
```

Registry auth is separate from cosign verification. For `registry.auth.password_file`, local file bundle refs, or `cosign.public_key_ref`, mount files with `extraVolumes` and `extraVolumeMounts` and point `password_file`, `ref`, or `public_key_ref` at the mounted path.

Required mode constrains the entries further, including digest pinning and the signed revision each entry must declare. See the [upstream configuration reference](https://github.com/Depthmark/github-sts#configuration) for those rules.

## GitHub Actions Usage

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - name: Get scoped GitHub token
        id: sts
        run: |
          OIDC_TOKEN=$(curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=github-sts" | jq -r '.value')

          GITHUB_TOKEN=$(curl -sf \
            -H "Authorization: Bearer $OIDC_TOKEN" \
            "${{ vars.STS_URL }}/sts/exchange?scope=${{ github.repository }}&app=default&identity=ci" \
            | jq -r '.token')

          echo "::add-mask::$GITHUB_TOKEN"
          echo "token=$GITHUB_TOKEN" >> $GITHUB_OUTPUT

      - name: Use scoped token
        env:
          GITHUB_TOKEN: ${{ steps.sts.outputs.token }}
        run: gh issue list
```

<!-- values:begin -->
## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules |
| audit.bufferSize | int | `1024` | Channel buffer size for async audit writes |
| audit.fileEnabled | bool | `true` | Enable audit file logging |
| audit.filePath | string | `"/var/log/github-sts/audit.json"` | Path to audit log file inside the container |
| autoscaling.behavior | object | `{}` | HPA scaling behavior (autoscaling/v2 `behavior` block). Tune scale-up and scale-down stabilization windows / policies to add backpressure when a webhook flood would otherwise saturate the existing replicas. Empty by default; the example below is a conservative starting point. |
| autoscaling.enabled | bool | `false` | Enable Horizontal Pod Autoscaler |
| autoscaling.maxReplicas | int | `10` | Maximum number of replicas |
| autoscaling.minReplicas | int | `2` | Minimum number of replicas |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage |
| bundles | list | `[]` | Signed Rego/OPA bundles evaluated after the YAML trust policy allows and before a GitHub installation token is minted. Entries are passed through to the server's top-level `bundles:` config without validation or renaming, so use the server's snake_case field names. Requires a server build with bundle support: v0.0.3 ignores the key silently and runs with no Rego layer. Such a build also requires a top-level `bundle_enforcement` value, which this chart does not render; set `GITHUBSTS_BUNDLE_ENFORCEMENT` through `extraEnv`. For a local file ref, `registry.auth.password_file`, or `cosign.public_key_ref`, mount the file with `extraVolumes` and `extraVolumeMounts` and point the field at the mounted path. |
| commonLabels | object | `{}` | Labels to add to all deployed objects |
| extraEnv | list | `[]` | Extra environment variables |
| extraVolumeMounts | list | `[]` | Extra volume mounts for the container |
| extraVolumes | list | `[]` | Extra volumes for the pod |
| fullnameOverride | string | `""` | Override the full release name |
| github.apps | object | `{}` | GitHub Apps map. At least one app must be configured. |
| httproute.annotations | object | `{}` | HTTPRoute annotations |
| httproute.enabled | bool | `false` | Enable HTTPRoute |
| httproute.hostnames | list | `[]` | Hostnames for routing |
| httproute.parentRefs | list | `[]` | Gateway parent references |
| httproute.port | int | `8080` | Port to route traffic to |
| image.digest | string | `""` | Image digest in `sha256:<hex>` form. When set, the chart renders `repository@digest` and `tag` is ignored. Pin by digest in production so the deployed bytes are immutable and verifiable by cosign / Kyverno `verifyImages` / Sigstore policy-controller. Tag-based pulls can silently change underneath you when a tag is overwritten upstream; digest pulls cannot. Use `crane digest <image:tag>` (or `docker buildx imagetools inspect`) to resolve a tag to its digest before setting this. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. With a tag pull, `IfNotPresent` is fine; with a digest pull, the kubelet treats the digest as immutable and skips re-pull regardless of policy. |
| image.registry | string | `"ghcr.io"` | Image registry |
| image.repository | string | `"depthmark/github-sts"` | Image repository |
| image.tag | string | `""` | Image tag (defaults to Chart.appVersion). Ignored when `digest` is set. |
| imagePullSecrets | list | `[]` | Secrets for pulling images from private registries |
| ingress.annotations | object | `{}` | Ingress annotations |
| ingress.className | string | `""` | Ingress class name |
| ingress.enabled | bool | `false` | Enable Ingress |
| ingress.hosts | list | `[{"host":"github-sts.example.com","paths":[{"path":"/","pathType":"Prefix"}]}]` | Ingress host rules |
| ingress.tls | list | `[]` | TLS configuration |
| jti.backend | string | `"memory"` | Backend: "memory" or "redis" |
| jti.redisUrl | string | `""` | Required if backend=redis |
| jti.ttl | string | `"1h"` | How long to remember consumed JTIs (Go duration string) |
| logging.level | string | `"info"` | Application log level (debug | info | warn | error) |
| logging.suppressHealthLogs | bool | `true` | Suppress health/ready/metrics access logs |
| metrics.authToken | string | `""` | Bearer token for /metrics endpoint (empty = unauthenticated) |
| metrics.enabled | bool | `true` | Enable Prometheus metrics endpoint |
| metrics.rateLimitPoll.enabled | bool | `true` | Enable periodic polling of GitHub rate limit API |
| metrics.rateLimitPoll.interval | string | `"60s"` | Polling interval (Go duration string) |
| metrics.reachabilityProbe.enabled | bool | `true` | Enable periodic GitHub API reachability probing |
| metrics.reachabilityProbe.interval | string | `"30s"` | Probe interval (Go duration string) |
| nameOverride | string | `""` | Override the chart name |
| networkPolicy.allowKubeDns | bool | `true` | Allow egress to kube-dns (UDP/TCP 53). Applies to whichever policy kinds are enabled. Required for any FQDN/external lookup to resolve. |
| networkPolicy.cilium.deriveJwksHostsFromIssuers | bool | `true` | Append issuer hosts and `oidc.trustedJwksHosts` values to the FQDN allow-list as `matchName` entries — issuer hosts cover the same-host JWKS case (GitHub Actions), trustedJwksHosts cover providers that publish JWKS on a different host (Google → www.googleapis.com). Disable to manage the FQDN list manually via `fqdns`. |
| networkPolicy.cilium.enabled | bool | `false` | Render a CiliumNetworkPolicy. |
| networkPolicy.cilium.extraEgress | list | `[]` | Free-form egress rules merged into the policy. |
| networkPolicy.cilium.extraIngress | list | `[]` | Free-form ingress rules merged into the policy. |
| networkPolicy.cilium.fqdns | list | `[]` | FQDNSelector entries allowed for egress on TCP 443. Each entry is a `matchName` or `matchPattern` map. |
| networkPolicy.cilium.fromEndpoints | list | `[]` | EndpointSelector entries allowed to reach the Service port. |
| networkPolicy.native.cidrs | list | `[]` | External CIDR ranges allowed for egress on TCP 443 (e.g. GitHub API, JWKS issuer hosts). Operators must populate this for their environment. |
| networkPolicy.native.enabled | bool | `false` | Render a native NetworkPolicy. Sets policyTypes: [Ingress, Egress]; rules not listed are denied. |
| networkPolicy.native.extraEgress | list | `[]` | Free-form egress rules merged into the policy (NetworkPolicyEgressRule shape). |
| networkPolicy.native.extraIngress | list | `[]` | Free-form ingress rules merged into the policy (NetworkPolicyIngressRule shape). |
| networkPolicy.native.from | list | `[]` | NetworkPolicyPeer entries allowed to reach the Service port. Empty list means no in-cluster ingress is permitted. |
| nodeSelector | object | `{}` | Node selector |
| oidc.allowedIssuers | list | `["https://token.actions.githubusercontent.com"]` | Allowed OIDC token issuers |
| oidc.requiredAudience | string | `""` | Server-wide required `aud` claim. When set, every token must carry this value before any policy lookup or JTI reservation runs — defense in depth on top of the per-policy `audience:` field. Leave empty to rely solely on per-policy `audience:` enforcement. Recommended in production: set this to the public URL of your STS deployment so a misconfigured or permissive policy file cannot accept tokens minted for an unrelated relying party. |
| oidc.trustedJwksHosts | object | `{}` | Per-issuer JWKS host overrides. Default behavior pins the JWKS `Host` header to the issuer host (so a malicious DNS answer for the issuer cannot redirect signing-key fetches elsewhere). This map is the escape hatch for issuers that legitimately publish JWKS on a different host — Google's `accounts.google.com` issues tokens but serves JWKS from `www.googleapis.com`, for example. Keys are full issuer URLs (with scheme), values are lists of allowed hostnames.  Verify before pinning:   curl -s https://accounts.google.com/.well-known/openid-configuration \     | jq -r .jwks_uri  When `networkPolicy.cilium.enabled=true`, hosts in this map are auto-appended to the FQDN egress allow-list alongside issuer hosts. Native NetworkPolicy users must add the corresponding CIDRs to `networkPolicy.native.cidrs` manually (no FQDN matching available). |
| pdb.enabled | bool | `true` | Create a PodDisruptionBudget. Recommended whenever replicaCount > 1 or autoscaling is enabled, so a node drain cannot evict every replica at once. |
| pdb.maxUnavailable | string | `nil` | Maximum number of pods that may be unavailable during a voluntary disruption. Set this OR minAvailable, not both. |
| pdb.minAvailable | int | `1` | Minimum number of pods that must remain available during a voluntary disruption. Mutually exclusive with maxUnavailable. Defaults to 1 when neither field is set. |
| podAnnotations | object | `{}` | Additional pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| podMonitor.annotations | object | `{}` | Annotations for the PodMonitor |
| podMonitor.enabled | bool | `false` | Whether to create a PodMonitor |
| podMonitor.honorLabels | bool | `false` | Honor labels |
| podMonitor.interval | string | `"30s"` | Scrape interval |
| podMonitor.labels | object | `{}` | Additional labels for the PodMonitor |
| podMonitor.metricRelabelings | list | `[]` | Metric relabeling configs |
| podMonitor.namespace | string | `""` | Namespace where the PodMonitor should be created (defaults to release namespace) |
| podMonitor.path | string | `"/metrics"` | Path to scrape metrics from |
| podMonitor.relabelings | list | `[]` | Relabeling configs |
| podMonitor.scheme | string | `""` | Scrape scheme. Empty means auto: `https` when `tls.enabled`, else `http`. Set explicitly only when something outside the chart (a mesh sidecar terminating TLS, for example) changes what the scraper sees. |
| podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| podMonitor.tlsConfig | object | `{}` | `tlsConfig` for the scrape endpoint. When `tls.enabled` is true and this is empty, the chart emits `insecureSkipVerify: true`, because Prometheus connects to a Pod IP that a normal serving certificate has no SAN for. That encrypts the scrape without authenticating the target — supply `ca` / `caFile` plus `serverName` to verify it properly, and `cert` + `keySecret` as well when `tls.clientAuth.enabled` is on, or scrapes will be rejected. |
| podSecurityContext.fsGroup | int | `65534` | Filesystem group |
| podSecurityContext.runAsGroup | int | `65534` | Primary GID for the container process. Pairs with `runAsUser` so the process has no group membership inherited from the image (some images ship with `gid=0` even when `uid` is non-root, which fails Pod Security Admission `restricted` and several CIS benchmarks). Distroless `nonroot` already provides gid 65534, so this is a defense-in-depth assertion rather than a behavior change for the default image. |
| podSecurityContext.runAsNonRoot | bool | `true` | Require non-root user |
| podSecurityContext.runAsUser | int | `65534` | UID to run as |
| podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile applied to all containers in the pod |
| policy.basePath | string | `".github/sts"` | Base path in repos for trust policies |
| policy.cacheTtl | string | `"60s"` | Cache TTL (Go duration string, e.g. "60s", "5m") |
| probes.liveness.enabled | bool | `true` | Enable liveness probe |
| probes.liveness.failureThreshold | int | `3` | Failure threshold for liveness probe |
| probes.liveness.initialDelaySeconds | int | `10` | Initial delay before liveness probe starts |
| probes.liveness.periodSeconds | int | `30` | Period between liveness probes |
| probes.liveness.timeoutSeconds | int | `3` | Timeout for liveness probe |
| probes.mode | string | `"auto"` | Probe transport for the startup / readiness / liveness probes. `auto` (default) picks `httpGet` over HTTP, `httpGet` over HTTPS when `tls.enabled`, and `tcpSocket` when `tls.clientAuth.enabled` — the kubelet cannot present a client certificate, so an HTTP probe against an mTLS listener fails the handshake and would crash-loop the pod. Force a specific transport with `httpGet` or `tcpSocket`; note that `tcpSocket` only proves the listener accepts connections, not that `/ready` returns 200. |
| probes.readiness.enabled | bool | `true` | Enable readiness probe |
| probes.readiness.failureThreshold | int | `3` | Failure threshold for readiness probe |
| probes.readiness.initialDelaySeconds | int | `5` | Initial delay before readiness probe starts |
| probes.readiness.periodSeconds | int | `10` | Period between readiness probes |
| probes.readiness.timeoutSeconds | int | `3` | Timeout for readiness probe |
| probes.startup.enabled | bool | `false` | Enable startup probe. When true, liveness/readiness are gated until this probe first succeeds. |
| probes.startup.failureThreshold | int | `30` | Number of consecutive failures before the kubelet gives up and restarts the container. Maximum startup time = `failureThreshold * periodSeconds` (default 30 * 5s = 150s). |
| probes.startup.initialDelaySeconds | int | `0` | Seconds the kubelet waits after the container starts before the first probe. Usually 0 since `failureThreshold * periodSeconds` already provides the startup budget. |
| probes.startup.periodSeconds | int | `5` | Seconds between probe attempts. Combined with `failureThreshold` it sets the maximum allowed startup time. |
| probes.startup.timeoutSeconds | int | `3` | Per-attempt HTTP timeout. Increase if startup work makes `/ready` respond slowly under contention. |
| rateLimit.burst | int | `20` | Maximum burst size per IP |
| rateLimit.enabled | bool | `false` | Enable per-IP rate limiting |
| rateLimit.exemptCidrs | list | `[]` | CIDR ranges exempt from rate limiting |
| rateLimit.rate | int | `10` | Requests per second per IP |
| replicaCount | int | `2` | Number of replicas. Defaulted to 2 so a node drain or single-pod OOM does not drop the webhook receiver entirely. Override to 1 only for dev. |
| resources | object | `{}` | Resource requests and limits |
| revisionHistoryLimit | int | `5` | Maximum number of old ReplicaSets retained for `kubectl rollout undo`. Each pod-template change (image bump, ConfigMap checksum change, values tweak) produces a new ReplicaSet; the old ones stay scaled to 0 as history. Higher = deeper rollback window but more etcd objects and `kubectl get rs` noise; lower = leaner cluster state but fewer rollback targets. Set to 0 to disable rollback entirely. The Kubernetes default is 10; 5 is a balance for this chart since `checksum/config` causes a roll on every config change. |
| securityContext.allowPrivilegeEscalation | bool | `false` | Disallow privilege escalation |
| securityContext.capabilities.drop | list | `["ALL"]` | Linux capabilities to drop |
| securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem |
| securityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for the container (overrides pod-level profile) |
| server.shutdownTimeout | string | `"10s"` | Graceful shutdown timeout (Go duration string) |
| server.trustForwardedHeaders | bool | `false` | Trust X-Forwarded-For headers for client IP (enable when behind a reverse proxy) |
| service.annotations | object | `{}` | Service annotations |
| service.appProtocol | string | `""` | Value for the Service port's `appProtocol` field. Empty means auto: `https` when `tls.enabled`, otherwise the field is omitted. Ingress controllers and mesh implementations use it to decide how to talk to the backend; it is advisory, so a controller that keys off its own annotation (e.g. `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`) still needs that annotation set as well. |
| service.port | int | `8080` | Service port |
| service.targetPort | int | `8080` | Container target port |
| service.type | string | `"ClusterIP"` | Service type |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automountServiceAccountToken | bool | `false` | Whether to automount the service account token |
| serviceAccount.create | bool | `true` | Whether to create a service account |
| serviceAccount.name | string | `""` | Name of the service account (defaults to fullname) |
| serviceMonitor.annotations | object | `{}` | Annotations for the ServiceMonitor |
| serviceMonitor.enabled | bool | `false` | Whether to create a ServiceMonitor |
| serviceMonitor.honorLabels | bool | `false` | Honor labels |
| serviceMonitor.interval | string | `"30s"` | Scrape interval |
| serviceMonitor.labels | object | `{}` | Additional labels for the ServiceMonitor |
| serviceMonitor.metricRelabelings | list | `[]` | Metric relabeling configs |
| serviceMonitor.namespace | string | `""` | Namespace where the ServiceMonitor should be created (defaults to release namespace) |
| serviceMonitor.path | string | `"/metrics"` | Path to scrape metrics from |
| serviceMonitor.relabelings | list | `[]` | Relabeling configs |
| serviceMonitor.scheme | string | `""` | Scrape scheme. Empty means auto: `https` when `tls.enabled`, else `http`. Set explicitly only when something outside the chart (a mesh sidecar terminating TLS, for example) changes what the scraper sees. |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| serviceMonitor.tlsConfig | object | `{}` | `tlsConfig` for the scrape endpoint. When `tls.enabled` is true and this is empty, the chart emits `insecureSkipVerify: true`, because Prometheus connects to a Pod IP that a normal serving certificate has no SAN for. That encrypts the scrape without authenticating the target — supply `ca` / `caFile` plus `serverName` to verify it properly, and `cert` + `keySecret` as well when `tls.clientAuth.enabled` is on, or scrapes will be rejected. |
| terminationGracePeriodSeconds | int | `30` | Pod terminationGracePeriodSeconds. Time the kubelet waits between SIGTERM and SIGKILL during pod shutdown. Must comfortably exceed `server.shutdownTimeout` (default 10s) plus probe drain time so in-flight `/sts/exchange` requests can complete before the container is killed. Setting this too low drops connections during rolling updates and node drains; setting it very high slows down voluntary disruptions but does not affect normal pod startup. |
| tests.enabled | bool | `true` | Render the `helm test` hook pods. Automatically skipped when `tls.clientAuth.enabled` is true, since the probe pods have no client certificate to present and every request would be rejected at the handshake. |
| tests.image | string | `"busybox:1.37"` | Image the test pods run. The test script uses `curl` when the image provides it and falls back to `wget`, so a curl image can be dropped in as is. Override the default when `tls.minVersion` is `"1.3"`: BusyBox's built-in TLS stack only speaks TLS 1.2 and the handshake would fail. |
| tls.certKey | string | `"tls.crt"` | Key inside `existingSecret` holding the PEM certificate chain. |
| tls.cipherSuites | list | `[]` | TLS 1.2 cipher suite allow-list, as IANA names (e.g. `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`). Empty means the Go defaults, which are already AEAD-only. Must be empty when `minVersion` is `"1.3"` — TLS 1.3 suites are not negotiable and the application rejects the combination at startup. |
| tls.clientAuth.caKey | string | `"ca.crt"` | Key inside the CA Secret holding the PEM CA bundle. |
| tls.clientAuth.enabled | bool | `false` | Require every client to present a certificate signed by the CA bundle in `clientAuth.caKey`. Verification is enforced for the whole listener — `/health`, `/ready` and `/metrics` included — so the chart switches the kubelet probes to `tcpSocket` (the kubelet cannot present a client certificate) and skips the `helm test` hooks. Prometheus needs client credentials in `serviceMonitor.tlsConfig` / `podMonitor.tlsConfig` to keep scraping. |
| tls.clientAuth.existingSecret | string | `""` | Existing Secret holding the trusted client CA bundle. Defaults to `tls.existingSecret`, which is convenient when cert-manager writes `ca.crt` alongside the serving cert. Point it at a separate Secret when the client CA is a different trust root than the serving CA. |
| tls.enabled | bool | `false` | Serve HTTPS directly from the pod. Switches the container port name to `https`, points the probes at the HTTPS scheme, and makes the chart mount `existingSecret` into the pod. Terminating at the ingress/Gateway remains the simpler model; reach for this only when the extra hop matters. |
| tls.existingSecret | string | `""` | Existing Secret holding the server certificate and private key. Required when `tls.enabled` is true. A standard `kubernetes.io/tls` Secret works as is (cert-manager, an internal PKI, or `kubectl create secret tls`); an Opaque Secret works too as long as `certKey` / `keyKey` name its keys. The chart never generates certificates — a self-signed cert is a local-testing tool, not a deployment target. |
| tls.keyKey | string | `"tls.key"` | Key inside `existingSecret` holding the PEM private key. |
| tls.minVersion | string | `"1.2"` | Minimum accepted TLS version: `"1.2"` or `"1.3"`. Raise to `"1.3"` when every client supports it — it removes the whole TLS 1.2 cipher negotiation surface, at the cost of rejecting older clients outright. |
| tls.mountPath | string | `"/etc/github-sts-tls"` | Directory the certificate material is mounted at. Deliberately *not* a subdirectory of `/etc/github-sts`: the config ConfigMap is mounted there read-only, and the container runtime cannot create a nested mountpoint inside a read-only mount (the pod would fail to start). |
| tls.reloadInterval | string | `""` | Certificate hot-reload poll interval (Go duration string, e.g. `"1h"`). Empty or `"0"` disables it. Kubernetes updates a mounted Secret in place on renewal, so without polling a cert-manager rotation only takes effect at the next pod restart. Set this to something well under the renewal window (cert-manager renews at 2/3 of lifetime by default) for rotation without a rollout. |
| tolerations | list | `[]` | Tolerations |
| topologySpreadConstraints | list | `[]` | Topology spread constraints |
<!-- values:end -->

## Ingress & Routing

### Ingress (Traditional)

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials" \
  --set ingress.enabled=true \
  --set ingress.className="nginx" \
  --set ingress.hosts[0].host="github-sts.example.com"
```

### HTTPRoute (Gateway API)

Requires Gateway API CRDs. HTTPRoute is more powerful and flexible than Ingress.

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials" \
  --set httproute.enabled=true \
  --set httproute.parentRefs[0].name="my-gateway" \
  --set httproute.hostnames[0]="github-sts.example.com"
```

## TLS & mTLS

The pod serves plain HTTP by default and TLS terminates in front of it, at the
ingress controller (`ingress.tls`) or the Gateway. Enable the `tls` block when
the hop between the proxy and the pod must be encrypted as well, when nothing
fronts the Service, or when clients must present a certificate.

```bash
kubectl create secret tls github-sts-tls --cert=tls.crt --key=tls.key

helm upgrade --install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials" \
  --set tls.enabled=true \
  --set tls.existingSecret=github-sts-tls \
  --set tls.reloadInterval=1h
```

The chart then mounts the certificate at `tls.mountPath`, renames the container
and Service port to `https`, and points the probes, the monitors, and the test
hooks at HTTPS. It does not reconfigure the proxy in front: that still needs its
own backend-protocol setting, such as
`nginx.ingress.kubernetes.io/backend-protocol: HTTPS` or a Gateway API
`BackendTLSPolicy`.

Adding `tls.clientAuth.enabled=true` requires and verifies a client certificate
on every endpoint, `/health`, `/ready`, and `/metrics` included. The probes fall
back to `tcpSocket` because the kubelet cannot present one, the `helm test`
hooks stop rendering for the same reason, and Prometheus needs client
credentials in `serviceMonitor.tlsConfig` or `podMonitor.tlsConfig`.

Requires a server image that supports the `server.tls` configuration section.
Full guidance, including certificate rotation, cipher suites, and verification
steps, is in [docs/content/en/tls.md](../../docs/content/en/tls.md).

## Testing

After deploying the chart, you can run the built-in Helm tests:

```bash
helm test github-sts
```

The tests validate:
- `/health` endpoint returns HTTP 200 with `{"status":"ok"}`
- `/ready` endpoint returns HTTP 200
- `/metrics` endpoint returns Prometheus metrics (when `metrics.enabled=true`)

They follow `tls.enabled` automatically (HTTPS without certificate verification)
and are skipped entirely under `tls.clientAuth.enabled`, since the hook pods have
no client certificate to present. The hook script prefers `curl` and falls back to
`wget`, so `tests.image` can be pointed at a curl image — required with
`tls.minVersion: "1.3"`, which BusyBox's TLS stack cannot negotiate.

## Upgrade

```bash
helm upgrade github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials"
```

## Uninstall

```bash
helm uninstall github-sts
```

## Features

- Multi-replica deployment support
- Health checks (readiness & liveness probes)
- Horizontal pod autoscaling
- Ingress support (traditional Kubernetes API)
- HTTPRoute support (Gateway API)
- Native TLS and mutual TLS termination in the pod, with certificate hot-reload
- Security context (non-root user, read-only filesystem)
- Resource limits and requests
- Prometheus metrics with ServiceMonitor / PodMonitor
- Support for existing secrets (no credentials in values)
- Multiple GitHub App support
- Helm test hooks for deployment validation

## Security

The chart enforces security best practices:
- Runs as non-root user (UID 65534)
- Read-only root filesystem
- No privilege escalation
- Dropped Linux capabilities
- Health probes for auto-recovery
- Private keys are mounted from existing Kubernetes Secrets (never stored in chart values)
- Optional end-to-end TLS with a configurable minimum version and cipher suite allow-list
- Optional mutual TLS, verifying client certificates against a trusted CA bundle
