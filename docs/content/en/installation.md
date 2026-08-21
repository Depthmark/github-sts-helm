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

## Load a signed policy bundle

`bundles` adds a Rego layer that runs after the YAML trust policy allows a request and before an installation token is minted. Each entry is written straight into the server configuration, so the fields are the server's snake_case names rather than the chart's camelCase.

Bundle support is newer than the server release this chart's `appVersion` pins. Do this in order.

### 1. Run a server build that supports bundles

Server `v0.0.3` ignores the `bundles:` key instead of rejecting it. The pod starts, exchanges succeed, and no Rego runs. Nothing in the chart or in the pod reports that, so move the image to a build with bundle support first, with `image.tag` or `image.digest` as above.

[Compatibility]({{< relref "/integrations/compatibility" >}}) lists the verified server, chart, and Action combinations.

### 2. Set the enforcement mode

A server with bundle support requires a top-level `bundle_enforcement` key set to `required` or `optional`, and refuses to start without it. The chart does not render that key, so set it through the environment:

```yaml
extraEnv:
  - name: GITHUBSTS_BUNDLE_ENFORCEMENT
    value: required
```

`required` is the production posture. `optional` lets the server run with no bundle installed, and it says so through a startup warning and through its health, metric, and audit output.

### 3. Configure the bundle

```yaml
bundles:
  - name: enterprise-baseline
    apps: []
    ref: oci://ghcr.io/example/github-sts-policy@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    expected_policy_revision: "42"
    poll_interval: 5m
    max_staleness: 10m
    fail_mode: closed
    cosign:
      certificate_identity_regexp: '^https://github\.com/example/github-sts-policy/\.github/workflows/release\.yml@refs/heads/main$'
      certificate_oidc_issuer: https://token.actions.githubusercontent.com
```

The server fetches the bundle itself, at runtime. `imagePullSecrets` covers the kubelet pulling the container image and has no effect here, and a NetworkPolicy that allows egress to the GitHub API does not allow egress to a bundle registry. [Networking]({{< relref "networking" >}}) covers the egress side.

Required mode constrains what an entry may look like, including digest pinning and the signed revision it must declare. [Configuration]({{< relref "/reference/configuration" >}}) is the reference for those rules.

### Mount a file a bundle entry needs

The chart mounts nothing on a bundle's behalf. A local file `ref`, a `registry.auth.password_file`, and a `cosign.public_key_ref` each name a path inside the container, so the file has to arrive through `extraVolumes` and `extraVolumeMounts`.

```bash
kubectl create secret generic github-sts-bundle \
  --namespace github-sts \
  --from-literal=registry-password=ghs_xxxxxxxxxxxxxxxxxxxx \
  --from-file=cosign.pub=./cosign.pub
```

```yaml
extraVolumes:
  - name: bundle
    secret:
      secretName: github-sts-bundle

extraVolumeMounts:
  - name: bundle
    mountPath: /var/run/secrets/bundle
    readOnly: true

bundles:
  - name: enterprise-baseline
    apps: []
    ref: oci://registry.internal.example.com/policy/github-sts@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    expected_policy_revision: "42"
    fail_mode: closed
    registry:
      auth:
        mode: basic
        username: robot$github-sts
        password_file: /var/run/secrets/bundle/registry-password
    cosign:
      public_key_ref: /var/run/secrets/bundle/cosign.pub
```

Registry authentication and cosign verification stay separate. The credential decides whether the pod can fetch the bundle. The cosign fields decide whether the fetched bundle is trusted.

### Verify

Render the ConfigMap to see what the server will read:

```bash
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --version 0.0.3 --values values.yaml \
  --show-only templates/configmap.yaml
```

Every field you set appears in the rendered block, with the keys of each entry sorted alphabetically. The chart does not validate the entries, so a misspelled field reaches the server unchanged and fails there rather than at render time.

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
