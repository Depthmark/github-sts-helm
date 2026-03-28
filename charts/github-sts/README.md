# GitHub STS Helm Chart

A Kubernetes Helm chart for deploying [github-sts](https://github.com/Depthmark/github-sts) — a Python-based Security Token Service (STS) for the GitHub API.

Workloads with OIDC tokens (GitHub Actions, Azure, Google Cloud, etc.) exchange them for short-lived, scoped GitHub installation tokens. No PATs required. Supports multiple GitHub Apps with YAML-based configuration (ideal for Kubernetes ConfigMaps).

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
     │  (or ?scope=myorg)       │                          │
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

### Organization-Level Scope

In addition to repository-level scope (`scope=org/repo`), github-sts supports organization-level scope (`scope=myorg`). To enable this, set `orgPolicyRepo` on the app configuration to specify where org-level trust policies live (e.g. `".github"`). Policies are then loaded from `{org}/{orgPolicyRepo}/{basePath}/{appName}/{identity}.sts.yaml`.

```yaml
github:
  apps:
    default:
      appId: "12345"
      existingSecret: "my-github-app-credentials"
      orgPolicyRepo: ".github"
```

See the [upstream documentation](https://github.com/Depthmark/github-sts#trust-policies) for full policy schema, org-level policy examples, and repository restrictions.

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

## Values Reference

### General

| Parameter | Default | Description |
|-----------|---------|-------------|
| `nameOverride` | `""` | Override the chart name |
| `fullnameOverride` | `""` | Override the full release name |
| `commonLabels` | `{}` | Labels to add to all deployed objects |
| `replicaCount` | `1` | Number of replicas |

### Image

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.registry` | `""` | Image registry (e.g., `ghcr.io`) |
| `image.repository` | `github-sts` | Image repository |
| `image.tag` | `""` | Image tag (defaults to Chart `appVersion`) |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `imagePullSecrets` | `[]` | Secrets for pulling images from private registries |

### Service Account

| Parameter | Default | Description |
|-----------|---------|-------------|
| `serviceAccount.create` | `true` | Whether to create a service account |
| `serviceAccount.annotations` | `{}` | Annotations to add to the service account |
| `serviceAccount.name` | `""` | Name of the service account (defaults to fullname) |
| `serviceAccount.automountServiceAccountToken` | `false` | Whether to automount the service account token |

### Service

| Parameter | Default | Description |
|-----------|---------|-------------|
| `service.type` | `ClusterIP` | Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) |
| `service.port` | `8080` | Service port |
| `service.targetPort` | `8080` | Container target port |
| `service.annotations` | `{}` | Service annotations |

### Ingress

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ingress.enabled` | `false` | Enable Ingress (traditional Kubernetes API) |
| `ingress.className` | `""` | Ingress class name (e.g., `nginx`) |
| `ingress.annotations` | `{}` | Ingress annotations |
| `ingress.hosts` | `[{host: "github-sts.example.com", paths: [{path: "/", pathType: "Prefix"}]}]` | Ingress host rules |
| `ingress.tls` | `[]` | TLS configuration |

### HTTPRoute (Gateway API)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `httproute.enabled` | `false` | Enable HTTPRoute (Gateway API) |
| `httproute.annotations` | `{}` | HTTPRoute annotations |
| `httproute.parentRefs` | `[]` | Gateway parent references |
| `httproute.hostnames` | `[]` | Hostnames for routing |
| `httproute.port` | `8080` | Port to route traffic to |

### Resources

| Parameter | Default | Description |
|-----------|---------|-------------|
| `resources` | `{}` | CPU/memory requests and limits |

### Autoscaling

| Parameter | Default | Description |
|-----------|---------|-------------|
| `autoscaling.enabled` | `false` | Enable Horizontal Pod Autoscaler |
| `autoscaling.minReplicas` | `2` | Minimum number of replicas |
| `autoscaling.maxReplicas` | `10` | Maximum number of replicas |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | Target CPU utilization percentage |
| `autoscaling.targetMemoryUtilizationPercentage` | — | Target memory utilization percentage |

### Probes

| Parameter | Default | Description |
|-----------|---------|-------------|
| `probes.liveness.enabled` | `true` | Enable liveness probe (`/health`) |
| `probes.liveness.initialDelaySeconds` | `10` | Initial delay before liveness probe |
| `probes.liveness.periodSeconds` | `30` | Period between liveness probes |
| `probes.liveness.timeoutSeconds` | `3` | Timeout for liveness probe |
| `probes.liveness.failureThreshold` | `3` | Failure threshold for liveness probe |
| `probes.readiness.enabled` | `true` | Enable readiness probe (`/ready`) |
| `probes.readiness.initialDelaySeconds` | `5` | Initial delay before readiness probe |
| `probes.readiness.periodSeconds` | `10` | Period between readiness probes |
| `probes.readiness.timeoutSeconds` | `3` | Timeout for readiness probe |
| `probes.readiness.failureThreshold` | `3` | Failure threshold for readiness probe |

### Security

| Parameter | Default | Description |
|-----------|---------|-------------|
| `podSecurityContext.runAsNonRoot` | `true` | Require non-root user |
| `podSecurityContext.runAsUser` | `1000` | UID to run as |
| `podSecurityContext.fsGroup` | `1000` | Filesystem group |
| `securityContext.allowPrivilegeEscalation` | `false` | Disallow privilege escalation |
| `securityContext.readOnlyRootFilesystem` | `true` | Read-only root filesystem |
| `securityContext.capabilities.drop` | `["ALL"]` | Linux capabilities to drop |

### Logging

| Parameter | Default | Description |
|-----------|---------|-------------|
| `logging.level` | `"INFO"` | Application log level (`DEBUG` \| `INFO` \| `WARNING` \| `ERROR`) |
| `logging.accessLevel` | `"INFO"` | Access log level (set to `DEBUG` to see health/ready requests) |
| `logging.suppressHealthLogs` | `true` | Suppress health/ready/metrics access logs at INFO level |
| `logging.audit.fileEnabled` | `true` | Write audit events to a rotating file |
| `logging.audit.filePath` | `"/var/log/github-sts/audit.json"` | Path to audit log file inside the container |
| `logging.audit.fileMaxBytes` | `10485760` | Max bytes per audit log file before rotation (10 MB) |
| `logging.audit.fileBackupCount` | `5` | Number of rotated audit log files to keep |

### Policy

| Parameter | Default | Description |
|-----------|---------|-------------|
| `policy.backend` | `"github"` | Policy storage backend |
| `policy.basePath` | `".github/sts"` | Base path in repos for trust policies |
| `policy.cacheTtlSeconds` | `60` | Policy cache TTL in seconds (0 = disable) |

### OIDC

| Parameter | Default | Description |
|-----------|---------|-------------|
| `oidc.allowedIssuers` | `["https://token.actions.githubusercontent.com"]` | Allowed OIDC issuers (empty list = allow any) |

### JTI Replay Prevention

| Parameter | Default | Description |
|-----------|---------|-------------|
| `jti.backend` | `"memory"` | JTI backend (`memory` \| `redis`) |
| `jti.redisUrl` | `""` | Redis connection URL (required if backend=redis) |
| `jti.ttlSeconds` | `3600` | How long to remember consumed JTIs |

### Audit (Legacy)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `audit.filePath` | `"/tmp/audit.log"` | Audit log file path |
| `audit.rotationPolicy` | `"daily"` | Rotation policy (`daily` \| `size`) |
| `audit.rotationSizeBytes` | `104857600` | Max bytes before rotation (100 MB) |

### Metrics

| Parameter | Default | Description |
|-----------|---------|-------------|
| `metrics.enabled` | `true` | Enable Prometheus metrics endpoint (`/metrics`) |
| `metrics.prefix` | `"pygithubsts"` | Metrics name prefix |
| `metrics.rateLimitPoll.enabled` | `true` | Enable periodic polling of GitHub rate limit API |
| `metrics.rateLimitPoll.intervalSeconds` | `60` | Rate limit polling interval in seconds |
| `metrics.reachabilityProbe.enabled` | `true` | Enable periodic GitHub API reachability probing |
| `metrics.reachabilityProbe.intervalSeconds` | `30` | Reachability probe interval in seconds |

### ServiceMonitor (Prometheus Operator)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `serviceMonitor.enabled` | `false` | Create a ServiceMonitor resource |
| `serviceMonitor.namespace` | `""` | Namespace for the ServiceMonitor (defaults to release namespace) |
| `serviceMonitor.labels` | `{}` | Additional labels |
| `serviceMonitor.annotations` | `{}` | Annotations |
| `serviceMonitor.interval` | `30s` | Scrape interval |
| `serviceMonitor.scrapeTimeout` | `10s` | Scrape timeout |
| `serviceMonitor.path` | `/metrics` | Metrics path |
| `serviceMonitor.metricRelabelings` | `[]` | Metric relabeling configs |
| `serviceMonitor.relabelings` | `[]` | Relabeling configs |
| `serviceMonitor.honorLabels` | `false` | Honor labels from the target |

### PodMonitor (Prometheus Operator)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `podMonitor.enabled` | `false` | Create a PodMonitor resource (alternative to ServiceMonitor) |
| `podMonitor.namespace` | `""` | Namespace for the PodMonitor (defaults to release namespace) |
| `podMonitor.labels` | `{}` | Additional labels |
| `podMonitor.annotations` | `{}` | Annotations |
| `podMonitor.interval` | `30s` | Scrape interval |
| `podMonitor.scrapeTimeout` | `10s` | Scrape timeout |
| `podMonitor.path` | `/metrics` | Metrics path |
| `podMonitor.metricRelabelings` | `[]` | Metric relabeling configs |
| `podMonitor.relabelings` | `[]` | Relabeling configs |
| `podMonitor.honorLabels` | `false` | Honor labels from the target |

### GitHub Apps (Required)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `github.apps` | `{}` | Map of GitHub App configurations. At least one app must be configured. |
| `github.apps.<name>.appId` | — | GitHub App numeric ID (required) |
| `github.apps.<name>.existingSecret` | — | Name of an existing Secret containing the private key (required) |
| `github.apps.<name>.secretPrivateKeyKey` | `"github-app-private-key"` | Key in the secret that holds the private key PEM |
| `github.apps.<name>.orgPolicyRepo` | — | Repository name for org-level trust policies (e.g. `".github"`). Enables organization-level scope for this app. |

### Pod Scheduling

| Parameter | Default | Description |
|-----------|---------|-------------|
| `podAnnotations` | `{}` | Additional pod annotations |
| `podLabels` | `{}` | Additional pod labels |
| `nodeSelector` | `{}` | Node selector |
| `tolerations` | `[]` | Tolerations |
| `affinity` | `{}` | Affinity rules |
| `topologySpreadConstraints` | `[]` | Topology spread constraints |

### Extensibility

| Parameter | Default | Description |
|-----------|---------|-------------|
| `extraEnv` | `[]` | Extra environment variables for the container |
| `extraVolumeMounts` | `[]` | Extra volume mounts for the container |
| `extraVolumes` | `[]` | Extra volumes for the pod |

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
- Runs as non-root user (UID 1000)
- Read-only root filesystem
- No privilege escalation
- Dropped Linux capabilities
- Health probes for auto-recovery
- Private keys are mounted from existing Kubernetes Secrets (never stored in chart values)
