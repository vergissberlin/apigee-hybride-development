# Contributing

Thanks for improving this project. This repository ships a **Docker image** for Apigee Hybrid development on Azure AKS. Contributions that keep the image maintainable, secure, and well documented are welcome.

## Ground rules

- Use **inclusive, respectful** communication in issues and pull requests.
- Do **not** commit secrets, tokens, kubeconfigs, or cloud credentials. Use local files or your own private environment; never open a PR that contains real credentials.
- Match existing style in the **Dockerfile** and docs: clear comments only where they add context, minimal churn in unrelated files.

## How to contribute

1. **Open an issue** first when you plan a larger change (new tools in the image, breaking base-image bumps, workflow changes). That avoids duplicate work and helps align on scope.
2. **Fork the repository**, create a branch from `main`, and open a **pull request** when your change is ready.
3. Describe **what** changed and **why** in the PR description. Link related issues when applicable.

## Local checks

Before opening a PR:

```bash
docker build -t apigee-hybrid-development:local .
```

If you changed tooling versions or install steps, run the container briefly and sanity-check the relevant CLI (`gcloud`, `az`, `kubectl`, `helm`, etc.).

## Commit messages

Use **[Conventional Commits](https://www.conventionalcommits.org/)** in English (for example `fix: pin kubectl apt repo`, `feat: add tool xyz`, `docs: clarify volume mounts`). This keeps the history readable and matches **[Release Please](.github/workflows/release-please.yml)**, which updates [CHANGELOG.md](CHANGELOG.md) from those commits.

Common types used here: `feat`, `fix`, `docs`, `perf`, `refactor`, `ci`, `chore`, `build`, `test`.

## Releases and CI

- **Release Please** runs on pushes to `main` and opens/maintains release PRs using [`.release-please-config.json`](.release-please-config.json).
- **Docker images** are built in [`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml) on pushes to `main`, on git tags matching `v*`, and via manual workflow dispatch. Published images are described in [README.md](README.md) (Docker Hub and GHCR).

Maintainers: if you cut release tags, keep them consistent with how registry tagging should work for consumers (see the workflow’s tag filters).

### Release Please: "not permitted to create or approve pull requests"

That error is controlled outside the workflow file. Fix it in one of two ways:

1. **Repository (or organization) settings** – allow Actions to open PRs: **Settings → Actions → General → Workflow permissions** — choose **Read and write permissions**, and enable **Allow GitHub Actions to create and approve pull requests**. If the option is grayed out, an org or enterprise admin must allow it at a higher level. See [GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#preventing-github-actions-from-creating-or-approving-pull-requests).

2. **Personal access token** – if policy forbids the above, add a repository secret **`RELEASE_PLEASE_TOKEN`** with a **classic** PAT that has the **`repo`** scope (so Release Please can push branches and open PRs). The workflow uses that token when the secret is set; otherwise it uses the default `GITHUB_TOKEN`.

## Documentation

- User-facing documentation in this repo is written in **English** (for example [README.md](README.md) and [docs/](docs/)).
- When you change how the image is built or run, update the README or the relevant doc under `docs/` in the same PR when practical.

## Editor configuration

The repo includes [`.editorconfig`](.editorconfig). Using an EditorConfig-aware editor helps keep formatting consistent.

## License

By contributing, you agree that your contributions will be licensed under the same terms as the project — see [LICENSE](LICENSE).
