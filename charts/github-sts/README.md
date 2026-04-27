# github-sts

![Version: 0.0.2](https://img.shields.io/badge/Version-0.0.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.2](https://img.shields.io/badge/AppVersion-0.0.2-informational?style=flat-square)

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

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules |
| audit.bufferSize | int | `1024` | Channel buffer size for async audit writes |
| audit.fileEnabled | bool | `true` | Enable audit file logging |
| audit.filePath | string | `"/var/log/github-sts/audit.json"` | Path to audit log file inside the container |
| autoscaling.enabled | bool | `false` | Enable Horizontal Pod Autoscaler |
| autoscaling.maxReplicas | int | `10` | Maximum number of replicas |
| autoscaling.minReplicas | int | `2` | Minimum number of replicas |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage |
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
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.registry | string | `"ghcr.io"` | Image registry |
| image.repository | string | `"depthmark/github-sts"` | Image repository |
| image.tag | string | `""` | Image tag (defaults to Chart.appVersion) |
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
| networkPolicy.cilium.deriveJwksHostsFromIssuers | bool | `true` | Append the host of each `oidc.allowedIssuers` URL to the FQDN allow-list as a `matchName` entry. Disable to manage the list manually. |
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
| podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| podSecurityContext.fsGroup | int | `65534` | Filesystem group |
| podSecurityContext.runAsNonRoot | bool | `true` | Require non-root user |
| podSecurityContext.runAsUser | int | `65534` | UID to run as |
| policy.basePath | string | `".github/sts"` | Base path in repos for trust policies |
| policy.cacheTtl | string | `"60s"` | Cache TTL (Go duration string, e.g. "60s", "5m") |
| probes.liveness.enabled | bool | `true` | Enable liveness probe |
| probes.liveness.failureThreshold | int | `3` | Failure threshold for liveness probe |
| probes.liveness.initialDelaySeconds | int | `10` | Initial delay before liveness probe starts |
| probes.liveness.periodSeconds | int | `30` | Period between liveness probes |
| probes.liveness.timeoutSeconds | int | `3` | Timeout for liveness probe |
| probes.readiness.enabled | bool | `true` | Enable readiness probe |
| probes.readiness.failureThreshold | int | `3` | Failure threshold for readiness probe |
| probes.readiness.initialDelaySeconds | int | `5` | Initial delay before readiness probe starts |
| probes.readiness.periodSeconds | int | `10` | Period between readiness probes |
| probes.readiness.timeoutSeconds | int | `3` | Timeout for readiness probe |
| rateLimit.burst | int | `20` | Maximum burst size per IP |
| rateLimit.enabled | bool | `false` | Enable per-IP rate limiting |
| rateLimit.exemptCidrs | list | `[]` | CIDR ranges exempt from rate limiting |
| rateLimit.rate | int | `10` | Requests per second per IP |
| replicaCount | int | `1` | Number of replicas |
| resources | object | `{}` | Resource requests and limits |
| securityContext.allowPrivilegeEscalation | bool | `false` | Disallow privilege escalation |
| securityContext.capabilities.drop | list | `["ALL"]` | Linux capabilities to drop |
| securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem |
| server.shutdownTimeout | string | `"10s"` | Graceful shutdown timeout (Go duration string) |
| server.trustForwardedHeaders | bool | `false` | Trust X-Forwarded-For headers for client IP (enable when behind a reverse proxy) |
| service.annotations | object | `{}` | Service annotations |
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
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| tolerations | list | `[]` | Tolerations |
| topologySpreadConstraints | list | `[]` | Topology spread constraints |

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

## Testing

After deploying the chart, you can run the built-in Helm tests:

```bash
helm test github-sts
```

The tests validate:
- `/health` endpoint returns HTTP 200 with `{"status":"ok"}`
- `/ready` endpoint returns HTTP 200
- `/metrics` endpoint returns Prometheus metrics (when `metrics.enabled=true`)

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
