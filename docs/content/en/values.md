---
title: Values Reference
description: Every value the github-sts chart accepts, with its default and its effect on the rendered manifests.
weight: 3
translationKey: helm-chart-values
---

This page is the configuration contract for the chart. It is checked against `charts/github-sts/values.yaml` on every pull request, so a value that exists here exists in the chart, and a value the chart accepts appears here.

Values that configure the *server* are written into the ConfigMap and read by the process at `/etc/github-sts/config.yaml`. Values that configure the *deployment* only affect the Kubernetes objects. The tables note which is which where it matters.

<!-- values:begin -->

## GitHub Apps

Required. A deployment with no app configured starts, serves `/health`, and rejects every exchange.

| Value | Default | Effect |
|---|---|---|
| `github.apps` | `{}` | Map of app name to app configuration. The map key is the app name a client sends as `app=`, and the directory a trust policy is read from. Each entry takes `appId`, `existingSecret`, and optionally `secretPrivateKeyKey` and `orgPolicyRepo`. |

Each entry accepts the following fields:

<!-- values:pause -->

| Field | Required | Effect |
|---|---|---|
| `appId` | Yes | Numeric GitHub App ID. Written to the ConfigMap as an integer. |
| `existingSecret` | Yes | Name of a Secret in the release namespace holding the App's private key. The chart never creates this Secret and no value accepts key material. |
| `secretPrivateKeyKey` | No | Key inside that Secret. Defaults to `github-app-private-key`. Only this key is projected into the pod. |
| `orgPolicyRepo` | No | Repository that holds organization-level trust policies, typically `.github`. Omit to resolve policies only from the target repository. |

<!-- values:resume -->

## Release identity

| Value | Default | Effect |
|---|---|---|
| `nameOverride` | `""` | Replaces the chart name in `app.kubernetes.io/name` and in generated object names. |
| `fullnameOverride` | `""` | Replaces the generated object name outright. Set this when the release name would produce an awkward prefix. |
| `commonLabels` | `{}` | Labels merged into every object the chart renders. Use it for ownership or cost-allocation labels. |
| `podAnnotations` | `{}` | Annotations added to the pod template, alongside the `checksum/config` annotation the chart already sets. |
| `podLabels` | `{}` | Labels added to the pod template. Selector labels are not affected, so adding one here does not orphan running pods. |

## Image

| Value | Default | Effect |
|---|---|---|
| `image.registry` | `"ghcr.io"` | Registry host, joined to `repository` with a slash. |
| `image.repository` | `"depthmark/github-sts"` | Image path within the registry. |
| `image.tag` | `""` | Image tag. Empty means the chart's `appVersion`, which is the version the chart was tested against. Ignored when `digest` is set. |
| `image.digest` | `""` | Digest in `sha256:<hex>` form. When set the chart renders `repository@digest`, which is what admission-time verification with cosign, Kyverno, or policy-controller attests to. A tag can be moved by anyone who can push; a digest cannot. |
| `image.pullPolicy` | `"IfNotPresent"` | Kubelet pull policy. With a digest pull the kubelet treats the reference as immutable and skips re-pulling regardless of this value. |
| `imagePullSecrets` | `[]` | List of `name` entries for pulling from a private registry. |

## Workload

| Value | Default | Effect |
|---|---|---|
| `replicaCount` | `2` | Replicas, when `autoscaling.enabled` is false. The default of 2 keeps the service up through a single node drain. Use 1 only in development. |
| `revisionHistoryLimit` | `5` | Old ReplicaSets kept for `kubectl rollout undo`. Every config change rolls the pods, because the pod template carries a checksum of the ConfigMap, so history accumulates faster here than in a typical chart. `0` disables rollback. |
| `terminationGracePeriodSeconds` | `30` | Seconds between SIGTERM and SIGKILL. Must exceed `server.shutdownTimeout` plus probe drain time, or in-flight exchanges are cut off during a rolling update. |
| `resources` | `{}` | Container requests and limits. Empty means unbounded, which leaves the pod in the `BestEffort` QoS class and first in line for eviction. Set both in production. |
| `nodeSelector` | `{}` | Node label selector for scheduling. |
| `tolerations` | `[]` | Taint tolerations for scheduling. |
| `affinity` | `{}` | Affinity and anti-affinity rules. |
| `topologySpreadConstraints` | `[]` | Spread constraints. Pair with `replicaCount` above 1 to keep replicas off one node or one zone. |
| `extraEnv` | `[]` | Additional container environment variables, in the core `EnvVar` shape. The chart already sets `GITHUBSTS_CONFIG_PATH`. |
| `extraVolumes` | `[]` | Additional pod volumes. |
| `extraVolumeMounts` | `[]` | Additional container volume mounts. The root filesystem is read-only, so any path the process must write to needs a volume here. |

## Availability

| Value | Default | Effect |
|---|---|---|
| `pdb.enabled` | `true` | Renders a PodDisruptionBudget, so a node drain cannot evict every replica at once. |
| `pdb.minAvailable` | `1` | Replicas that must stay available during a voluntary disruption. Mutually exclusive with `maxUnavailable`. |
| `pdb.maxUnavailable` | `null` | Replicas that may be unavailable during a voluntary disruption. Set this or `minAvailable`, never both. |
| `autoscaling.enabled` | `false` | Renders a HorizontalPodAutoscaler and drops `replicas` from the Deployment, handing replica count to the HPA. |
| `autoscaling.minReplicas` | `2` | Lower bound for the HPA. |
| `autoscaling.maxReplicas` | `10` | Upper bound for the HPA. |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | CPU utilization target. Requires a CPU request in `resources`, since utilization is a percentage of the request. |
| `autoscaling.behavior` | `{}` | The `autoscaling/v2` `behavior` block. Use it to slow scale-down or to cap scale-up so a burst of exchanges cannot fan out replicas faster than GitHub's rate limit allows. |

## Probes

All three probes hit the container's HTTP port. Liveness uses `/health`; readiness and startup use `/ready`.

| Value | Default | Effect |
|---|---|---|
| `probes.startup.enabled` | `false` | Adds a startup probe. While it runs, liveness and readiness are suspended, which is what lets a slow cold start avoid a liveness restart loop. Enable it when JWKS fetching or a large JTI cache restore can outlast the liveness budget. |
| `probes.startup.initialDelaySeconds` | `0` | Delay before the first startup attempt. Usually 0, because the threshold already provides the budget. |
| `probes.startup.periodSeconds` | `5` | Seconds between startup attempts. |
| `probes.startup.timeoutSeconds` | `3` | Per-attempt timeout. |
| `probes.startup.failureThreshold` | `30` | Attempts before the kubelet restarts the container. Maximum startup time is `failureThreshold * periodSeconds`, 150 seconds by default. |
| `probes.liveness.enabled` | `true` | Adds a liveness probe on `/health`. A failure restarts the container. |
| `probes.liveness.initialDelaySeconds` | `10` | Delay before the first liveness attempt. |
| `probes.liveness.periodSeconds` | `30` | Seconds between liveness attempts. |
| `probes.liveness.timeoutSeconds` | `3` | Per-attempt timeout. |
| `probes.liveness.failureThreshold` | `3` | Consecutive failures before a restart. |
| `probes.readiness.enabled` | `true` | Adds a readiness probe on `/ready`. A failure removes the pod from Service endpoints without restarting it. |
| `probes.readiness.initialDelaySeconds` | `5` | Delay before the first readiness attempt. |
| `probes.readiness.periodSeconds` | `10` | Seconds between readiness attempts. |
| `probes.readiness.timeoutSeconds` | `3` | Per-attempt timeout. |
| `probes.readiness.failureThreshold` | `3` | Consecutive failures before the pod leaves the endpoint list. |

## Security context and identity

The defaults satisfy Pod Security Admission `restricted`. Weakening any of them is a deliberate decision, not a tuning step.

| Value | Default | Effect |
|---|---|---|
| `podSecurityContext.runAsNonRoot` | `true` | Refuses to start the pod if the image resolves to UID 0. |
| `podSecurityContext.runAsUser` | `65534` | UID for every container in the pod, matching the distroless `nonroot` image. |
| `podSecurityContext.runAsGroup` | `65534` | Primary GID, so the process inherits no group membership from the image. Some otherwise non-root images still ship `gid=0`. |
| `podSecurityContext.fsGroup` | `65534` | Group applied to mounted volumes. |
| `podSecurityContext.seccompProfile` | `{"type":"RuntimeDefault"}` | Pod-level seccomp profile. |
| `securityContext.allowPrivilegeEscalation` | `false` | Blocks setuid binaries from raising privileges. |
| `securityContext.readOnlyRootFilesystem` | `true` | Makes the root filesystem read-only. The chart mounts `emptyDir` volumes for `/tmp` and, when audit logging is on, for the audit directory. |
| `securityContext.capabilities.drop` | `["ALL"]` | Linux capabilities dropped from the container. |
| `securityContext.seccompProfile` | `{"type":"RuntimeDefault"}` | Container-level seccomp profile, overriding the pod-level one. |
| `serviceAccount.create` | `true` | Renders a dedicated ServiceAccount instead of reusing `default`. |
| `serviceAccount.name` | `""` | Name of the ServiceAccount. Empty means the generated object name when `create` is true, and `default` when it is false. |
| `serviceAccount.annotations` | `{}` | Annotations on the ServiceAccount, such as an IRSA or Workload Identity binding. |
| `serviceAccount.automountServiceAccountToken` | `false` | Off by default: the server talks to GitHub, never to the Kubernetes API, so a projected API token in the pod would be reachable credential material with no legitimate use. |

## Service and routing

See [Networking]({{< relref "networking" >}}) for worked examples.

| Value | Default | Effect |
|---|---|---|
| `service.type` | `"ClusterIP"` | Service type. |
| `service.port` | `8080` | Port the Service listens on. |
| `service.targetPort` | `8080` | Container port. Also written into the ConfigMap as the port the server binds. |
| `service.annotations` | `{}` | Service annotations, such as internal load balancer hints. |
| `ingress.enabled` | `false` | Renders an Ingress. |
| `ingress.className` | `""` | `ingressClassName` on the Ingress. |
| `ingress.annotations` | `{}` | Ingress annotations, such as `cert-manager.io/cluster-issuer`. |
| `ingress.hosts` | host `github-sts.example.com`, path `/` with `pathType: Prefix` | Host and path rules. Replace the placeholder host before enabling. |
| `ingress.tls` | `[]` | TLS blocks. An Ingress with no TLS block serves the exchange endpoint over plaintext HTTP, which exposes the bearer OIDC token in transit. |
| `httproute.enabled` | `false` | Renders a Gateway API HTTPRoute. Requires the Gateway API CRDs. |
| `httproute.parentRefs` | `[]` | Gateways the route attaches to. |
| `httproute.hostnames` | `[]` | Hostnames the route matches. |
| `httproute.port` | `8080` | Backend Service port the route forwards to. |
| `httproute.annotations` | `{}` | HTTPRoute annotations. |

## NetworkPolicy

Both policy kinds default to off. Enable the one your CNI implements, or both.

| Value | Default | Effect |
|---|---|---|
| `networkPolicy.allowKubeDns` | `true` | Adds a DNS egress rule on UDP and TCP 53 to whichever policy kinds are enabled. Without it no hostname resolves and every exchange fails. |
| `networkPolicy.native.enabled` | `false` | Renders a `networking.k8s.io/v1` NetworkPolicy with `policyTypes: [Ingress, Egress]`. Anything not listed is denied. |
| `networkPolicy.native.from` | `[]` | Peers allowed to reach the Service port. An empty list denies all in-cluster ingress, which also blocks `helm test`. |
| `networkPolicy.native.cidrs` | `[]` | CIDR ranges allowed for egress on TCP 443. The native API cannot match by hostname, so GitHub and JWKS ranges must be listed and maintained by hand. |
| `networkPolicy.native.extraIngress` | `[]` | Extra rules merged into the policy, in `NetworkPolicyIngressRule` shape. |
| `networkPolicy.native.extraEgress` | `[]` | Extra rules merged into the policy, in `NetworkPolicyEgressRule` shape. |
| `networkPolicy.cilium.enabled` | `false` | Renders a `cilium.io/v2` CiliumNetworkPolicy. Requires the Cilium CRD. |
| `networkPolicy.cilium.fromEndpoints` | `[]` | Endpoint selectors allowed to reach the Service port. |
| `networkPolicy.cilium.fqdns` | `[]` | FQDN selectors allowed for egress on TCP 443, each a `matchName` or `matchPattern` map. |
| `networkPolicy.cilium.deriveJwksHostsFromIssuers` | `true` | Appends every `oidc.allowedIssuers` host and every `oidc.trustedJwksHosts` value to the FQDN allow-list, so adding an issuer does not silently break its key fetch. Disable to manage `fqdns` by hand. |
| `networkPolicy.cilium.extraIngress` | `[]` | Extra ingress rules merged into the policy. |
| `networkPolicy.cilium.extraEgress` | `[]` | Extra egress rules merged into the policy. |

## Server and logging

| Value | Default | Effect |
|---|---|---|
| `server.shutdownTimeout` | `"10s"` | Graceful shutdown budget, as a Go duration. Must stay below `terminationGracePeriodSeconds`. |
| `server.trustForwardedHeaders` | `false` | Reads the client IP from `X-Forwarded-For`. Enable only behind a proxy that overwrites the header, because a trusted header on a directly reachable server lets a caller forge the IP that rate limiting and audit records key on. |
| `logging.level` | `"info"` | Application log level: debug, info, warn, or error. |
| `logging.suppressHealthLogs` | `true` | Drops access log lines for `/health`, `/ready`, and `/metrics`, which otherwise dominate the log at probe frequency. |

## Trust policy and OIDC

| Value | Default | Effect |
|---|---|---|
| `policy.basePath` | `".github/sts"` | Directory in the target repository holding trust policies. A policy resolves to `{basePath}/{app}/{identity}.sts.yaml`. |
| `policy.cacheTtl` | `"60s"` | How long a fetched policy is reused. Higher values cut GitHub API calls; lower values shorten the window in which a revoked policy is still honored. |
| `oidc.allowedIssuers` | `["https://token.actions.githubusercontent.com"]` | Issuers whose tokens are accepted. A token whose `iss` is not listed is rejected before any policy lookup. Keep this list as short as the deployment allows. |
| `oidc.requiredAudience` | `""` | Server-wide required `aud` claim, checked before policy lookup and before JTI reservation. Empty means per-policy `audience:` enforcement only. Set it to this deployment's public URL, so one permissive policy file cannot accept a token minted for another relying party. |
| `oidc.trustedJwksHosts` | `{}` | Per-issuer JWKS host allow-list. By default the JWKS `Host` header is pinned to the issuer host, so a forged DNS answer cannot redirect a signing-key fetch. This map is the exception for issuers that publish keys elsewhere, such as `accounts.google.com` serving from `www.googleapis.com`. Keys are full issuer URLs, values are host lists. |

## Replay prevention

| Value | Default | Effect |
|---|---|---|
| `jti.backend` | `"memory"` | Where consumed token IDs are recorded: `memory` or `redis`. `memory` is per-pod, so with more than one replica a token replayed against a different pod is not detected. Use `redis` whenever `replicaCount` is above 1 or autoscaling is on. |
| `jti.redisUrl` | `""` | Redis connection URL. Required when `backend` is `redis`. |
| `jti.ttl` | `"1h"` | How long a consumed token ID is remembered. Keep it at or above the longest accepted token lifetime, or a token becomes replayable before it expires. |

## Rate limiting

| Value | Default | Effect |
|---|---|---|
| `rateLimit.enabled` | `false` | Enables per-IP rate limiting on `/sts/exchange`. |
| `rateLimit.rate` | `10` | Sustained requests per second per IP. |
| `rateLimit.burst` | `20` | Burst allowance per IP. |
| `rateLimit.exemptCidrs` | `[]` | CIDR ranges exempt from the limit. Exempt only ranges you control: the limit is keyed on the client IP, which is only as trustworthy as `server.trustForwardedHeaders` makes it. |

## Audit

| Value | Default | Effect |
|---|---|---|
| `audit.fileEnabled` | `true` | Writes the audit stream to a file. The chart mounts a 100 MiB `emptyDir` for it, because the root filesystem is read-only. |
| `audit.filePath` | `"/var/log/github-sts/audit.json"` | Path inside the container. Its parent directory is what the chart mounts, so changing this moves the mount with it. |
| `audit.bufferSize` | `1024` | Channel buffer for asynchronous audit writes. |

An `emptyDir` is deleted with the pod. Ship the audit stream off the node with a log collector if you need it to survive a restart.

## Metrics

| Value | Default | Effect |
|---|---|---|
| `metrics.enabled` | `true` | Serves Prometheus metrics on `/metrics` and enables the chart's metrics test hook. |
| `metrics.authToken` | `""` | Bearer token required on `/metrics`. Empty leaves the endpoint unauthenticated, which is normally fine for a `ClusterIP` Service and not fine for one exposed through an Ingress. |
| `metrics.rateLimitPoll.enabled` | `true` | Polls the GitHub rate limit API so remaining quota is visible before exchanges start failing. |
| `metrics.rateLimitPoll.interval` | `"60s"` | Poll interval for the rate limit API. |
| `metrics.reachabilityProbe.enabled` | `true` | Probes GitHub API reachability on a timer, which separates an egress failure from a policy failure during an incident. |
| `metrics.reachabilityProbe.interval` | `"30s"` | Reachability probe interval. |

### ServiceMonitor

Requires the Prometheus Operator CRDs. Scrapes through the Service.

| Value | Default | Effect |
|---|---|---|
| `serviceMonitor.enabled` | `false` | Renders a ServiceMonitor. |
| `serviceMonitor.namespace` | `""` | Namespace for the object. Empty means the release namespace. |
| `serviceMonitor.labels` | `{}` | Extra labels, typically the label your Prometheus instance selects on. |
| `serviceMonitor.annotations` | `{}` | Extra annotations. |
| `serviceMonitor.interval` | `"30s"` | Scrape interval. |
| `serviceMonitor.scrapeTimeout` | `"10s"` | Scrape timeout. Keep it below the interval. |
| `serviceMonitor.path` | `"/metrics"` | Metrics path. |
| `serviceMonitor.metricRelabelings` | `[]` | Relabeling applied to scraped samples. |
| `serviceMonitor.relabelings` | `[]` | Relabeling applied to the target before scraping. |
| `serviceMonitor.honorLabels` | `false` | Lets scraped labels win over target labels on collision. |

### PodMonitor

The alternative to ServiceMonitor: scrapes pods directly, which is what you want when the Service is not the scrape path.

| Value | Default | Effect |
|---|---|---|
| `podMonitor.enabled` | `false` | Renders a PodMonitor. |
| `podMonitor.namespace` | `""` | Namespace for the object. Empty means the release namespace. |
| `podMonitor.labels` | `{}` | Extra labels, typically the label your Prometheus instance selects on. |
| `podMonitor.annotations` | `{}` | Extra annotations. |
| `podMonitor.interval` | `"30s"` | Scrape interval. |
| `podMonitor.scrapeTimeout` | `"10s"` | Scrape timeout. Keep it below the interval. |
| `podMonitor.path` | `"/metrics"` | Metrics path. |
| `podMonitor.metricRelabelings` | `[]` | Relabeling applied to scraped samples. |
| `podMonitor.relabelings` | `[]` | Relabeling applied to the target before scraping. |
| `podMonitor.honorLabels` | `false` | Lets scraped labels win over target labels on collision. |

<!-- values:end -->

Enabling both monitors double-scrapes the same series. Pick one.

## Next

- [Rendered Resources]({{< relref "resources" >}}) for what these values produce
- [Networking]({{< relref "networking" >}}) for the routing and policy values in context
- [Configuration]({{< relref "/reference/configuration" >}}) for what the server does with the rendered config file
