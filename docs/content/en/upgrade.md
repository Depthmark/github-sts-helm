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

## Routes now publish `/sts/` only

Earlier chart releases defaulted `ingress.hosts[].paths` to `/` with `pathType: Prefix`, and rendered the HTTPRoute with a hard-coded `PathPrefix` match on `/`. Either one published `/health`, `/ready`, and `/metrics` on the public hostname alongside the exchange endpoint. Both now default to `/sts/`.

The upgrade narrows the route unless your values file sets the path itself. Two things to check before rolling it out:

- Anything outside the cluster that calls `/health`, `/ready`, or `/metrics` through the route — an external uptime check, a Prometheus that scrapes through the load balancer — stops resolving. Move it in-cluster, or add the path back explicitly.
- A values file that pins `path: /` keeps the wide route. Narrowing it is a values change, and [Networking]({{< relref "networking" >}}) covers what the wide route exposes.

`httproute.paths` is new, and it may not be empty: Gateway API reads a rule with no matches as matching every path, so the chart fails to render rather than publish everything.

## What triggers a restart

The pod template carries `checksum/config`, a hash of the rendered ConfigMap. Any change to a server-side value — an issuer, an audience, a log level, a policy TTL — changes that hash and rolls the pods. This is deliberate: the server reads its configuration at startup, so a ConfigMap update that did not roll the pods would leave the running process on the old configuration with no signal that it had diverged.

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

A rollback restores the ConfigMap along with the Deployment, so it undoes a server configuration change as well as an image change.

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
