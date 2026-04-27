.PHONY: lint lint-ci template unittest ci clean helm-docs helm-docs-check act act-lint act-unittest act-integration

# Lint chart (strict mode)
lint:
	helm lint charts/github-sts --strict

# Lint chart with all CI value files
lint-ci:
	@for f in charts/github-sts/ci/*.yaml; do \
		echo "=== Linting with $${f} ==="; \
		helm lint charts/github-sts --strict -f "$${f}"; \
	done

# Render templates
template:
	helm template test charts/github-sts

# Run unit tests
unittest:
	helm unittest charts/github-sts

# Run all local checks
ci: lint lint-ci template unittest helm-docs-check

# Generate helm documentation
helm-docs:
	helm-docs

# Check that helm documentation is up to date
helm-docs-check:
	helm-docs
	@git diff --quiet -- charts/*/README.md || (echo "ERROR: README.md is out of date. Run 'make helm-docs' and commit the changes." && exit 1)

# Clean generated artifacts
clean:
	rm -f rendered.yaml

# Run all CI jobs locally with act
act:
	act pull_request --workflows .github/workflows/ci.yml

# Run individual CI jobs locally with act
act-lint:
	act pull_request --workflows .github/workflows/ci.yml --job helm-lint

act-unittest:
	act pull_request --workflows .github/workflows/ci.yml --job helm-unittest

act-integration:
	act pull_request --workflows .github/workflows/integration.yml
