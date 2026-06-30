# Security Policy

## Supported Surface

This repository publishes a static GitHub Pages site from `docs/`.

The public site does not require login, store user accounts, or implement SSO. Access control for repository administration, GitHub Pages deployment, and secrets belongs in GitHub account or organization settings, not in the static Quarto site.

## Secrets And Private Data

Do not commit:

- `.env`, `.Renviron`, API keys, or credentials
- raw paid-provider data
- private local database files
- token-bearing logs

The repository `.gitignore` excludes these files. Public pages should only contain rendered summaries, metadata, and model outputs intended for sharing.

## Recommended GitHub Controls

- Enable two-factor authentication on the GitHub account or organization.
- Require SAML/SSO only if the repository moves under a GitHub Enterprise organization that supports it.
- Keep GitHub Pages deployment scoped to the `github-pages` environment.
- Store API keys only as GitHub Actions secrets.
- Review Actions permissions before adding new workflows.
- Use Dependabot for GitHub Actions updates.

## Reporting

If you find a secret exposure or security issue, do not open a public issue with the secret value. Rotate the credential first, then use GitHub private vulnerability reporting or contact the repository owner through the LindaData GitHub account.
