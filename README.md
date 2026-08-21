# github-sts-helm

Helm chart for deploying [github-sts](https://github.com/Depthmark/github-sts) — a Python-based Security Token Service (STS) that exchanges OIDC tokens for short-lived, scoped GitHub installation tokens.

## Quick Start

```bash
# Create a secret with your GitHub App private key
kubectl create secret generic my-github-app-credentials \
  --from-file=github-app-private-key=/path/to/private_key.pem

# Install from OCI registry
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --set github.apps.default.appId="YOUR_GITHUB_APP_ID" \
  --set github.apps.default.existingSecret="my-github-app-credentials"
```

## Documentation

See the [chart README](charts/github-sts/README.md) for full configuration options, values reference, Ingress/HTTPRoute setup, and more examples.

## Development

The hooks require Node.js and `helm-docs` on `PATH`. This Homebrew setup installs them with [`prek`](https://github.com/j178/prek), the Rust-based pre-commit hook runner. The current hook configuration targets the `helm-docs` v1.14.2 wrapper.

```bash
brew trust --formula norwoodj/tap/helm-docs
brew install prek node norwoodj/tap/helm-docs
make hooks
```

Run every hook against the repository to verify the setup:

```bash
prek run --all-files
```

The hooks regenerate `charts/github-sts/README.md` from the chart values and template, then check that the published documentation matches the chart. Commit the regenerated README whenever a chart change updates it.

## Links

- [github-sts](https://github.com/Depthmark/github-sts) — Upstream service
- [Chart source](charts/github-sts/) — Helm chart files
- [OCI package](https://github.com/orgs/Depthmark/packages?repo_name=github-sts-helm) — Published chart

## License

MIT
