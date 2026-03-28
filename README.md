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

## Links

- [github-sts](https://github.com/Depthmark/github-sts) — Upstream service
- [Chart source](charts/github-sts/) — Helm chart files
- [OCI package](https://github.com/orgs/Depthmark/packages?repo_name=github-sts-helm) — Published chart

## License

MIT