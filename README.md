# github-sts-helm

Helm chart for deploying [github-sts](https://github.com/Depthmark/github-sts) — a Security Token Service (STS) that exchanges OIDC tokens for short-lived, scoped GitHub installation tokens.

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

The hooks require Node.js, Go and `helm-docs` on `PATH`. This Homebrew setup installs them with [`prek`](https://github.com/j178/prek), the Rust-based pre-commit hook runner. The current hook configuration targets the `helm-docs` v1.14.2 wrapper, and builds [`helm-schema`](https://github.com/dadav/helm-schema) 0.23.5 from source, which is why Go is needed.

```bash
brew trust --formula norwoodj/tap/helm-docs
brew install prek node go norwoodj/tap/helm-docs
make hooks
```

`make ci` and `make schema` call `helm-schema` directly, so install the same version on `PATH` as well. `go install` puts it in `$(go env GOPATH)/bin`, which has to be on `PATH`:

```bash
go install github.com/dadav/helm-schema/cmd/helm-schema@0.23.5
export PATH="$(go env GOPATH)/bin:$PATH"   # add this line to ~/.zshrc to keep it
```

`make ci` also runs the unit tests, which need the helm-unittest plugin:

```bash
helm plugin install --verify=false https://github.com/helm-unittest/helm-unittest.git
```

Run every hook against the repository to verify the setup:

```bash
prek run --all-files
```

The hooks regenerate `charts/github-sts/values.schema.json` from the `# @schema` blocks in `values.yaml` and `charts/github-sts/README.md` from the chart values and template, then check that the published documentation matches the chart. Commit the regenerated files whenever a chart change updates them. Never edit `values.schema.json` by hand: a value the schema should accept or reject is described by a `# @schema` block above its key in `values.yaml`.

## Links

- [github-sts](https://github.com/Depthmark/github-sts) — Upstream service
- [Chart source](charts/github-sts/) — Helm chart files
- [OCI package](https://github.com/orgs/Depthmark/packages?repo_name=github-sts-helm) — Published chart

## License

MIT
