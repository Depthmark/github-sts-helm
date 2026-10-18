.PHONY: lint lint-ci template unittest ci clean schema schema-check require-helm-schema helm-docs helm-docs-check docs-check hooks act act-lint act-unittest act-integration

# helm-schema flags, shared by `make schema`, `make schema-check` and CI. The
# prek hook in .pre-commit-config.yaml repeats them; keep the two in step.
HELM_SCHEMA_FLAGS := --chart-search-root=charts --skip-auto-generation=required --no-dependencies --append-newline

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

# Run all local checks. schema-check comes first: lint, template and unittest
# all validate against values.schema.json, so a stale one would mislead them.
ci: schema-check lint lint-ci template unittest helm-docs-check docs-check

# Generate values.schema.json from the @schema annotations in values.yaml
schema: require-helm-schema
	helm-schema $(HELM_SCHEMA_FLAGS)

# Check that values.schema.json matches values.yaml, without writing it
schema-check: require-helm-schema
	@helm-schema $(HELM_SCHEMA_FLAGS) --check || (echo "ERROR: values.schema.json is out of date. Run 'make schema' and commit the changes." && exit 1)

# Fail with the install command, not a misleading "out of date", when the
# binary is missing
require-helm-schema:
	@command -v helm-schema >/dev/null 2>&1 || (echo "ERROR: helm-schema is not on PATH. Install it with 'go install github.com/dadav/helm-schema/cmd/helm-schema@0.23.5' and put \$$(go env GOPATH)/bin on PATH." && exit 1)

# Generate helm documentation
helm-docs:
	helm-docs

# Check that helm documentation is up to date
helm-docs-check:
	helm-docs
	@git diff --quiet -- charts/*/README.md || (echo "ERROR: README.md is out of date. Run 'make helm-docs' and commit the changes." && exit 1)

# Check that docs/content matches the chart. Runs helm-docs first, because the
# check reads the generated README as the list of public chart values.
docs-check: helm-docs
	node docs/scripts/check-docs.js

# Install the prek hooks that run helm-docs and docs-check on commit
hooks:
	prek install

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
