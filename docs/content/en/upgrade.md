---
title: Upgrade
description: Roll a new chart or image version, understand what triggers a pod restart, and roll back when it goes wrong.
weight: 7
translationKey: helm-chart-upgrade
---

## Upgrade the chart

```bash
helm upgrade github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts \
  --version 0.0.3 \
  --values values.yaml
```

Two habits make this safe.

Pass `--values` on every upgrade. Helm does not carry forward the values from the previous release unless you ask it to with `--reuse-values`, and mixing the two across upgrades is how a setting silently reverts to its default. Keep the values file in version control and treat it as the source of truth.

Pass `--version` on every upgrade. Without it Helm resolves whatever is newest in the registry at that moment, which makes the deployed version depend on when the command ran.

Review the change before applying it:

```bash
helm diff upgrade github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts --version 0.0.3 --values values.yaml
```

`helm diff` is the [helm-diff](https://github.com/databus23/helm-diff) plugin. Without it, `helm template ... | kubectl diff -f -` gets you most of the way.

## Migrate metrics endpoint authentication

`metrics.authToken` is deprecated. It remains functional during migration, but do not set it together with `endpointAuth.metricsToken` or `endpointAuth.existingSecret`: the chart rejects both combinations at render time rather than discarding the deprecated value without warning.

Move the value to the new key:

```yaml
endpointAuth:
  metricsToken: "replace-with-your-metrics-token"
```

Before this change, `metrics.authToken` rendered as `metrics.auth_token` in the server ConfigMap. After the upgrade, the chart removes `auth_token` from the ConfigMap, writes the token to its endpoint-auth Secret, and injects `GITHUBSTS_METRICS_AUTH_TOKEN` from that Secret. This also applies while the deprecated value is still in use.

To manage the Secret outside Helm, create it in the release namespace before the upgrade:

```bash
kubectl create secret generic github-sts-endpoint-auth \
  --namespace github-sts \
  --from-file=metrics-auth-token=/path/to/protected/metrics-token \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl describe secret github-sts-endpoint-auth --namespace github-sts
```

Confirm that `metrics-auth-token` appears in the `Data` section, then set `endpointAuth.existingSecret: github-sts-endpoint-auth` and `endpointAuth.metricsKey: metrics-auth-token`. Check it again after the upgrade and after every rotation. The Deployment marks the Secret and key references optional, so a missing object or key lets the pod start with endpoint authentication disabled. The default HTTP liveness probe also cannot read an external Secret to construct an `Authorization` header, so this configuration requires `probes.mode: tcpSocket` while liveness is enabled.

## What triggers a restart

The pod template carries `checksum/config`, a hash of the rendered ConfigMap. Any change to a server-side value — an issuer, an audience, a log level, a policy TTL — changes that hash and rolls the pods. This is deliberate: the server reads its configuration at startup, so a ConfigMap update that did not roll the pods would leave the running process on the old configuration with no signal that it had diverged.

The pod template also carries `checksum/secret`. Changing an inline endpoint token changes the chart-owned Secret and rolls the pods. Changing the contents of `endpointAuth.existingSecret` does not change that checksum, and environment variables sourced from a Secret are resolved when the pod starts. Restart the Deployment after rotating an external endpoint-auth Secret, or configure a Secret reloader.

The practical consequence is that this chart rolls more often than a typical one. `revisionHistoryLimit` defaults to `5` for the same reason.

A rolling update drains through `terminationGracePeriodSeconds`, defaulting to 30 seconds, and the server's own `server.shutdownTimeout`, defaulting to 10 seconds. In-flight exchanges complete as long as the grace period stays comfortably above the shutdown timeout.

## Upgrade the server image

`image.tag` follows the chart's `appVersion`, so a chart upgrade normally carries the matching server image with it. Override the image only to move the two independently:

```yaml
image:
  tag: "0.0.3"
```

In a cluster with admission-time image verification, pin `image.digest` instead and leave `tag` empty. See [Installation]({{< relref "installation" >}}).

Check [Compatibility]({{< relref "/integrations/compatibility" >}}) before moving the server image away from the chart's `appVersion`. That page lists the verified combinations of server, chart, and action releases.

## Change the private key

The chart mounts the key from a Secret it does not own, so rotating a key is a two-step operation:

```bash
kubectl create secret generic github-sts-default-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./new-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/github-sts --namespace github-sts
```

Updating the Secret alone does not restart anything, and the server holds the key it read at startup. The restart is what puts the new key in use. Generate the new key in GitHub and let both keys work before you delete the old one, so a pod that has not rolled yet keeps functioning.

## Roll back

```bash
helm history github-sts --namespace github-sts
helm rollback github-sts 3 --namespace github-sts
```

`revisionHistoryLimit` bounds how far back `kubectl rollout undo` can reach at the ReplicaSet level. Helm's own history is separate and is bounded by `--history-max` on the client, so the two do not necessarily agree on how far back you can go.

A rollback restores the ConfigMap and chart-owned endpoint-auth Secret along with the Deployment, so it undoes a server configuration or inline token change as well as an image change.

## Before a production upgrade

1. Read the [chart changelog](https://github.com/Depthmark/github-sts-helm/blob/main/charts/github-sts/CHANGELOG.md) for the versions you are crossing.
2. Check [Compatibility]({{< relref "/integrations/compatibility" >}}) for the server and action versions you run.
3. Diff the render against the cluster.
4. Confirm `pdb.enabled` is true and `replicaCount` is above 1, so the roll cannot take the service down.
5. Upgrade, then run `helm test`.

## Next

- [Versioning]({{< relref "versioning" >}}) for how chart versions are produced
- [Values Reference]({{< relref "values" >}}) for the values an upgrade may change
- [Upgrades]({{< relref "/operations/upgrades" >}}) for the server's own upgrade guidance
