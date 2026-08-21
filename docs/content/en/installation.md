---
title: Installation
description: Install from the OCI package, configure several GitHub Apps, pull from a private registry, and pin the image by digest.
weight: 2
translationKey: helm-chart-installation
---

Each pattern below assumes the prerequisites from the [Quickstart]({{< relref "quickstart" >}}): a namespace, a registered GitHub App, and its private key stored in a Kubernetes Secret you created.

## Install from the OCI package

The chart is published as an OCI artifact. There is no chart repository to add, and no `helm repo update` step.

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts --create-namespace \
  --version 0.0.3 \
  --values values.yaml
```

Every published version is signed with [cosign](https://docs.sigstore.dev/cosign/overview/) and carries a build provenance attestation. Verify both before installing into a production cluster:

```bash
cosign verify ghcr.io/depthmark/charts/github-sts:0.0.3 \
  --certificate-identity-regexp '^https://github\.com/Depthmark/github-sts-helm/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/depthmark/charts/github-sts:0.0.3 \
  --repo Depthmark/github-sts-helm
```

To inspect a version without installing it:

```bash
helm show values oci://ghcr.io/depthmark/charts/github-sts --version 0.0.3
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts --version 0.0.3 --values values.yaml
```

## Configure several GitHub Apps

One deployment can serve several GitHub Apps. Each entry under `github.apps` needs its own App ID and its own Secret, because each App has its own private key.

```bash
kubectl create secret generic github-sts-ci-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./ci-app.private-key.pem

kubectl create secret generic github-sts-release-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./release-app.private-key.pem
```

```yaml
github:
  apps:
    ci:
      appId: "123456"
      existingSecret: github-sts-ci-app
    release:
      appId: "654321"
      existingSecret: github-sts-release-app
      orgPolicyRepo: .github
```

The chart mounts each key at `/etc/github-sts/apps/{app}/{key}` and writes a matching `private_key_path` into the ConfigMap. Nothing is shared between apps, so a client that asks for `app=ci` can never be signed by the release App's key.

The app name is part of the trust policy path. With the values above, a client sending `app=release&identity=deploy` resolves the policy at `.github/sts/release/deploy.sts.yaml` in the target repository. `orgPolicyRepo` lets the `release` App fall back to a policy stored centrally in the organization's `.github` repository; see [Trust Policies]({{< relref "/concepts/trust-policies" >}}) for the resolution order.

### Name the key inside the Secret

`secretPrivateKeyKey` overrides the default key name, which is useful when the Secret is managed by an external secrets operator that dictates its own layout.

```yaml
github:
  apps:
    ci:
      appId: "123456"
      existingSecret: github-sts-ci-app
      secretPrivateKeyKey: tls.key
```

The chart projects only that one key into the pod. Other keys in the same Secret are not mounted.

## Pull from a private registry

Mirror the image and point the chart at your registry:

```yaml
image:
  registry: registry.internal.example.com
  repository: platform/github-sts

imagePullSecrets:
  - name: internal-registry
```

`image.registry` and `image.repository` are joined, so the example above pulls `registry.internal.example.com/platform/github-sts`.

## Pin the image by digest

`image.tag` defaults to the chart's `appVersion`. A tag is a mutable pointer: whoever can push to the registry can move it. `image.digest` is not.

```bash
crane digest ghcr.io/depthmark/github-sts:0.0.3
```

```yaml
image:
  digest: sha256:3f79bb7b435b05321651daefd374cdc681dc06faa65e374e38337b88ca046dea
```

When `digest` is set the chart renders `repository@digest` and ignores `tag` entirely. Pin by digest in any cluster running admission-time image verification — cosign, Kyverno `verifyImages`, or Sigstore policy-controller — because those policies attest to a digest, not to a tag.

## Install without cluster-wide CRDs

The chart's optional objects each depend on an API group that may not be installed:

| Value | Requires |
|---|---|
| `httproute.enabled` | Gateway API CRDs (`gateway.networking.k8s.io`) |
| `networkPolicy.cilium.enabled` | Cilium CRDs (`cilium.io/v2`) |
| `serviceMonitor.enabled`, `podMonitor.enabled` | Prometheus Operator CRDs (`monitoring.coreos.com/v1`) |

All four default to `false`, so a default install needs no CRD beyond core Kubernetes. Enabling one whose CRD is absent makes `helm install` fail at apply time with `no matches for kind`.

## Verify a change before applying it

`helm template` renders locally without contacting the cluster, which makes it the cheapest way to review a values change:

```bash
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --version 0.0.3 --values values.yaml \
  | kubectl diff --namespace github-sts -f -
```

## Uninstall

```bash
helm uninstall github-sts --namespace github-sts
```

Helm removes everything it created. The private key Secrets survive, because the chart never owned them. Delete them separately when you are decommissioning the deployment for good.

## Next

- [Networking]({{< relref "networking" >}}) to expose the Service and restrict its egress
- [Values Reference]({{< relref "values" >}}) for every value the chart accepts
- [Rendered Resources]({{< relref "resources" >}}) for what each template produces
