---
title: Helm Chart
description: Deploy github-sts on Kubernetes with the official Helm chart, from a signed OCI package.
weight: 1
translationKey: helm-chart
aliases:
  - /integrations/deploy-with-helm/
---

[github-sts-helm](https://github.com/Depthmark/github-sts-helm) packages the github-sts server for Kubernetes. It renders a Deployment, a Service, and a ConfigMap holding the server configuration, and it mounts each GitHub App private key from a Secret you create yourself. The chart never holds a private key in its values.

The chart is published as a signed OCI artifact at `ghcr.io/depthmark/charts/github-sts` and carries build provenance attestation.

{{< cards >}}
{{< card link="quickstart" title="Quickstart" icon="play" subtitle="A working single-app deployment, from an empty namespace" >}}
{{< card link="installation" title="Installation" icon="download" subtitle="OCI install, multiple apps, private registries, digest pinning" >}}
{{< card link="values" title="Values Reference" icon="adjustments" subtitle="Every chart value, with its default and its effect" >}}
{{< card link="resources" title="Rendered Resources" icon="cube" subtitle="What each template renders and what gates it" >}}
{{< card link="networking" title="Networking" icon="globe-alt" subtitle="Ingress, HTTPRoute, and NetworkPolicy for both CNI families" >}}
{{< card link="upgrade" title="Upgrade" icon="arrow-circle-up" subtitle="Rolling a new chart or image version, and rolling it back" >}}
{{< card link="versioning" title="Versioning" icon="tag" subtitle="Chart pinning, release process, and supported combinations" >}}
{{< /cards >}}

## Where this documentation ends

This section documents the chart: its values, the Kubernetes objects it renders, its upgrade path, and its versioning.

Server behavior lives elsewhere in this site. What the server does with the configuration this chart writes is described in [Configuration]({{< relref "/reference/configuration" >}}), trust policy fields and evaluation in [Trust Policies]({{< relref "/concepts/trust-policies" >}}), and the exchange endpoint in the [API Reference]({{< relref "/reference/api" >}}). The client side of the exchange is documented in [GitHub Action]({{< relref "/integrations/github-action" >}}).
