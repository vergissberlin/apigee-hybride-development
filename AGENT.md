# AGENT Rules

Guidance for automated and human agents working in this repository. Prefer **small, focused changes** that match existing style.

## Project context

- This repo maintains a **Docker image** for developing and operating **[Apigee Hybrid](https://cloud.google.com/apigee/docs/hybrid)** on **Azure AKS**.
- Base image: `vergissberlin/ubuntu-development:24.04` (see [Dockerfile](Dockerfile)).
- Primary artifacts: **Dockerfile**, **docs/**, and **GitHub Actions** under `.github/workflows/`.

## Commit messages

- Use **[Conventional Commits](https://www.conventionalcommits.org/)** in **English** for every commit message (for example `feat:`, `fix:`, `docs:`, `ci:`, `chore:`).
- Align types with [Release Please](.github/workflows/release-please.yml) sections in [`.release-please-config.json`](.release-please-config.json) so changelog generation stays consistent.

## Code and Dockerfile changes

- Change only what the task requires; avoid drive-by refactors or unrelated formatting.
- Follow [Dockerfile](Dockerfile) patterns: `DEBIAN_FRONTEND=noninteractive`, `apt-get install` with `--no-install-recommends`, clean `rm -rf /var/lib/apt/lists/*` after apt steps.
- **amd64** is assumed (Azure CLI apt repo, etc.); do not add multi-arch or ARM without an explicit task and Dockerfile updates.
- After Dockerfile edits, assume contributors will run `docker build -t apigee-hybrid-development:local .`; keep layers cache-friendly where reasonable.

## Documentation

- User-facing documentation ([README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md), [docs/](docs/)) must be in **English**.
- When behavior or image usage changes, update the relevant doc in the **same change** when practical.

## Security and configuration

- **Never** commit secrets, tokens, kubeconfigs, or cloud credentials. Do not paste real credentials into issues or PRs.
- Prefer local configuration via ignored files (e.g. `.env` for local tooling); this image repo should not ship credential files.

## CI and releases

- **Release Please** ([`.github/workflows/release-please.yml`](.github/workflows/release-please.yml)) manages release PRs from conventional commits. If Actions cannot open PRs, see [CONTRIBUTING.md](CONTRIBUTING.md) (repository settings or `RELEASE_PLEASE_TOKEN`). Unparsed commits in logs are a changelog concern, not the same as the PR-permission error—details there.
- **Docker publish** ([`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)) pushes to Docker Hub and GHCR; image naming and secrets are documented in the workflow comments and [README.md](README.md).
- When editing workflows, keep `permissions:` minimal and document new required **secrets** in comments or CONTRIBUTING.

## Style and tooling

- Respect [.editorconfig](.editorconfig): UTF-8, LF, final newline, trim trailing whitespace; **4 spaces** in the Dockerfile, **2 spaces** in YAML and typical text files.
