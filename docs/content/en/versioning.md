---
title: Versioning
description: How to pin the chart, how chart releases are produced, and where the supported version combinations are published.
weight: 7
translationKey: helm-chart-versioning
---

## Choose a reference

| Reference | Example | Use when |
|---|---|---|
| Chart version | `--version 0.0.3` | Default choice. You review upgrades explicitly. |
| Chart digest | `oci://ghcr.io/depthmark/charts/github-sts@sha256:...` | You require a reference that cannot be moved, or your policy engine verifies the chart artifact. |
| No version flag | *(omitted)* | Never. Helm resolves the newest published chart, so the deployed version becomes a function of when the command ran. |

The chart deploys a service that mints credentials. Treat it the way you treat any other privileged dependency and pin it, in the values file and in whatever CD tool applies it.

While the major version is `0`, a breaking change increments the minor version rather than the major. Read the [chart changelog](https://github.com/Depthmark/github-sts-helm/blob/main/charts/github-sts/CHANGELOG.md) across every version you cross, not only the one you land on.

## Chart version and app version

`Chart.yaml` carries two versions, and they mean different things.

| Field | Meaning |
|---|---|
| `version` | The chart's own version. It changes when templates or values change, including when nothing about the server changed. |
| `appVersion` | The github-sts server release the chart was built and tested against. It is the default for `image.tag`. |

They currently track each other, but nothing guarantees they always will. Pin the chart with `--version`, and pin the server image separately with `image.tag` or `image.digest` when you need the two to move independently.

## How releases are produced

The repository uses [Release Please](https://github.com/googleapis/release-please) with [conventional commits](https://www.conventionalcommits.org/).

1. Commits land on `main` with a conventional prefix, such as `feat:` or `fix:`.
2. Release Please maintains a release pull request carrying the `Chart.yaml` bump and the changelog entry.
3. Merging that pull request creates the GitHub release and the tag, which is component-scoped: `github-sts-v0.0.3`.
4. The release workflow packages the chart, publishes it to `ghcr.io/depthmark/charts/github-sts`, signs it with cosign, and attaches a build provenance attestation.
5. The workflow refuses to publish if the tag version and the `Chart.yaml` version disagree.

The release workflow authenticates to GitHub with [github-sts-action]({{< relref "/integrations/github-action" >}}) rather than with a stored credential, so the repository holds no personal access token for its own releases.

## Which server release to run against

Verified combinations of server, chart, and action releases are published in [Compatibility]({{< relref "/integrations/compatibility" >}}). Check that page before upgrading one component on its own, particularly before overriding `image.tag` away from the chart's `appVersion`.

## How this documentation is published

The pages in this section live in the chart's repository, under `docs/content/`, and are pulled into this site as a [Hugo module](https://gohugo.io/hugo-modules/) pinned to a specific version. The site build resolves that version through the Go module proxy, so a documentation build is reproducible and never picks up unreviewed content from a default branch.

The module is declared at the repository root rather than in `docs/`, so it carries the repository's own version and needs no separate documentation tag. The chart's release tags are component-prefixed — `github-sts-v0.0.3` — which the Go module proxy does not read as a module version, so the site pins the commit SHA of the release instead. The proxy resolves that to a pseudo-version, which is as immutable as a tag.

Publishing a documentation change therefore takes two merges: one in the chart repository, and one in the site repository that moves the pin forward. That second merge is the review gate.
