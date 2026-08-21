---
title: Rendered Resources
description: Every Kubernetes object the chart renders, the value that gates it, and the API group it needs.
weight: 4
translationKey: helm-chart-resources
---

This page maps each template in the chart to the object it produces. It is checked against `charts/github-sts/templates` on every pull request, so a template that exists is listed here.

Render the set yourself for any values file before applying it:

```bash
helm template github-sts charts/github-sts --values values.yaml
```

## Always rendered

<!-- resources:begin -->

| Template | Kind | Notes |
|---|---|---|
| `deployment.yaml` | `apps/v1` Deployment | The server. Carries a `checksum/config` pod annotation, so any change to the rendered configuration rolls the pods rather than leaving them on stale config. |
| `configmap.yaml` | `v1` ConfigMap | The server configuration, mounted read-only at `/etc/github-sts/config.yaml` and located by the `GITHUBSTS_CONFIG_PATH` environment variable. Named `{fullname}-config`. |
| `service.yaml` | `v1` Service | Fronts the pods on `service.port`, targeting the container's named `http` port. |
| `secret.yaml` | none | Renders nothing. The file is a placeholder recording that the chart deliberately does not create a Secret: every GitHub App private key comes from an `existingSecret` you own. |

## Conditionally rendered

| Template | Kind | Rendered when |
|---|---|---|
| `serviceaccount.yaml` | `v1` ServiceAccount | `serviceAccount.create` is true. Set `serviceAccount.name` and turn `create` off to reuse an existing account. |
| `poddisruptionbudget.yaml` | `policy/v1` PodDisruptionBudget | `pdb.enabled` is true, which is the default. Uses `minAvailable`, or `maxUnavailable` when only that is set, and falls back to `minAvailable: 1`. |
| `hpa.yaml` | `autoscaling/v2` HorizontalPodAutoscaler | `autoscaling.enabled` is true. The Deployment then omits `replicas`, so `replicaCount` no longer applies. |
| `ingress.yaml` | `networking.k8s.io/v1` Ingress | `ingress.enabled` is true. |
| `httproute.yaml` | `gateway.networking.k8s.io/v1` HTTPRoute | `httproute.enabled` is true. Requires the Gateway API CRDs. |
| `networkpolicy.yaml` | `networking.k8s.io/v1` NetworkPolicy | `networkPolicy.native.enabled` is true. |
| `ciliumnetworkpolicy.yaml` | `cilium.io/v2` CiliumNetworkPolicy | `networkPolicy.cilium.enabled` is true. Requires the Cilium CRD. |
| `servicemonitor.yaml` | `monitoring.coreos.com/v1` ServiceMonitor | `serviceMonitor.enabled` is true. Requires the Prometheus Operator CRDs. |
| `podmonitor.yaml` | `monitoring.coreos.com/v1` PodMonitor | `podMonitor.enabled` is true. Requires the Prometheus Operator CRDs. |

## Test hooks

These are `helm.sh/hook: test` Pods. They are created by `helm test`, not by `helm install`, and are deleted on success and before the next run.

| Template | Pod | Asserts |
|---|---|---|
| `tests/test-connection.yaml` | `{fullname}-test-health` | `/health` returns HTTP 200 with `{"status":"ok"}`. |
| `tests/test-readiness.yaml` | `{fullname}-test-ready` | `/ready` returns HTTP 200. |
| `tests/test-metrics.yaml` | `{fullname}-test-metrics` | `/metrics` serves Prometheus text. Rendered only when `metrics.enabled` is true. |

<!-- resources:end -->

A NetworkPolicy that denies in-cluster ingress also denies the test Pods. Add their namespace to `networkPolicy.native.from` or `networkPolicy.cilium.fromEndpoints` if you want `helm test` to keep working under a policy.

## The pod

The Deployment renders one container with a fixed shape.

| Mount | Source | Why |
|---|---|---|
| `/etc/github-sts` | ConfigMap, read-only | The server configuration file. |
| `/etc/github-sts/apps/{app}` | Secret, read-only | One mount per `github.apps` entry, projecting only the configured private key. |
| `/tmp` | `emptyDir` | The root filesystem is read-only, so scratch space has to be a volume. |
| Parent of `audit.filePath` | `emptyDir`, 100 MiB | Rendered only when `audit.fileEnabled` is true. Deleted with the pod, so ship the stream off-node if you need it to survive. |

The container listens on `service.targetPort` as the named port `http`, and serves:

| Path | Used by |
|---|---|
| `/sts/exchange` | Clients exchanging an OIDC token. |
| `/health` | The liveness probe and the `test-health` hook. |
| `/ready` | The readiness probe, the startup probe, and the `test-ready` hook. |
| `/metrics` | Prometheus, the monitors, and the `test-metrics` hook. Rendered only when `metrics.enabled` is true. |

## Labels

Every object carries the standard recommended labels — `app.kubernetes.io/name`, `instance`, `version`, `managed-by`, and `helm.sh/chart` — plus anything in `commonLabels`. Selector labels are `name` and `instance` only, so adding a `commonLabels` entry does not change the selector and does not orphan running pods.

## Next

- [Values Reference]({{< relref "values" >}}) for the values that gate these objects
- [Networking]({{< relref "networking" >}}) for the routing and policy objects in context
- [Upgrade]({{< relref "upgrade" >}}) for how a change to these objects rolls out
