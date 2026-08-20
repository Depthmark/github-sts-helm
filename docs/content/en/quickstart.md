---
title: Quickstart
description: Install the chart into an empty namespace with one GitHub App, and verify that the server is ready to exchange tokens.
weight: 1
translationKey: helm-chart-quickstart
---

This page takes an empty Kubernetes namespace and leaves you with a running github-sts server that can mint installation tokens for one GitHub App.

**Audience:** a cluster operator with `helm` and `kubectl` access to a namespace.

**Goal:** a `Ready` deployment that answers `/ready` and passes `helm test`.

## Prerequisites

1. Kubernetes 1.19 or later, and Helm 3.
2. A GitHub App registered and installed on the repositories you intend to scope tokens to. See [Configure the GitHub App]({{< relref "/get-started/configure-github-app" >}}).
3. The App's private key as a PEM file on your workstation.

The chart does not create a Secret for the private key, and no chart value accepts key material. You create the Secret; the chart mounts it read-only.

## Steps

### 1. Create the namespace and the private key Secret

```bash
kubectl create namespace github-sts

kubectl create secret generic github-sts-default-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./default-app.private-key.pem
```

The key inside the Secret must be named `github-app-private-key`, or you must name it yourself with `github.apps.<name>.secretPrivateKeyKey`.

### 2. Write a values file

```yaml
# values.yaml
github:
  apps:
    default:
      appId: "123456"
      existingSecret: github-sts-default-app

oidc:
  allowedIssuers:
    - https://token.actions.githubusercontent.com
  requiredAudience: https://sts.example.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

The map key under `github.apps` is the app name. It is not cosmetic: it selects the directory a trust policy is read from, `.github/sts/{app}/{identity}.sts.yaml`, and it is what a client sends as the `app` request parameter.

`oidc.requiredAudience` is a server-wide floor on the `aud` claim, checked before any policy is loaded. Set it to the public URL of this deployment so a permissive policy file cannot accept a token minted for an unrelated relying party.

### 3. Install the chart

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts \
  --version 0.0.3 \
  --values values.yaml
```

Always pass `--version`. Without it Helm resolves the newest published chart, which makes the deployed version a function of when you ran the command.

## Expected result

Two replicas reach `Running`, because `replicaCount` defaults to `2`:

```bash
kubectl get pods --namespace github-sts
```

```text
NAME                          READY   STATUS    RESTARTS   AGE
github-sts-6d4f8b9c7d-4nzq2   1/1     Running   0          40s
github-sts-6d4f8b9c7d-x8k5m   1/1     Running   0          40s
```

The release notes print the port-forward command for the default `ClusterIP` Service, and warn if `github.apps` is empty.

## Verification

Run the chart's own tests. They create short-lived Pods that curl the server from inside the cluster and are deleted afterwards.

```bash
helm test github-sts --namespace github-sts
```

The tests assert that `/health` returns `{"status":"ok"}`, that `/ready` returns HTTP 200, and — when `metrics.enabled` is true, as it is by default — that `/metrics` serves Prometheus text.

Check the configuration the chart rendered, which is the file the server actually reads:

```bash
kubectl get configmap github-sts-config --namespace github-sts -o jsonpath='{.data.config\.yaml}'
```

Confirm the private key is mounted where the configuration expects it:

```bash
kubectl exec --namespace github-sts deploy/github-sts -- \
  ls /etc/github-sts/apps/default
```

## Limitations

- The chart configures the server but never contacts GitHub itself. A wrong `appId`, an uninstalled App, or a missing trust policy surfaces on the first exchange, not at install time.
- `/ready` reports process readiness. It does not prove that GitHub is reachable or that a JWKS endpoint resolves. Egress problems appear as failed exchanges and in the reachability metric.
- No Ingress or HTTPRoute is created by default. Until you enable one, the Service is reachable only from inside the cluster.

## Next

- [Installation]({{< relref "installation" >}}) for several GitHub Apps, private registries, and digest pinning
- [Networking]({{< relref "networking" >}}) to expose the Service and restrict its egress
- [Values Reference]({{< relref "values" >}}) for the full value surface
