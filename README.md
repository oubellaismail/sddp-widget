# sddp-service-template

The **paved road** for a new service on the Secure-by-Default Delivery Platform.
Create a repo from this template and you inherit — in one click — the full secure
pipeline: a PR CI gate (secret scan, SAST, SCA, Dockerfile lint, build + image
scan), and a post-merge release that generates an SBOM, keyless-signs the image,
promotes it to the production registry, and opens a digest-bump PR against the
project config repo. A hardened, non-root, zero-CVE-base Dockerfile ships with it.

> **The deal:** the security controls are the default. You write the service; the
> road carries the scanning, signing, provenance, and GitOps delivery for free.

---

## 1. Create your service (one click, nothing to run)

1. Click **"Use this template" → Create a new repository**.
2. **Name it `sddp-<your-service>`** (e.g. `sddp-widget`). That's the only knob —
   the pipeline derives everything from the repo name at runtime:
   - image → `ghcr.io/<owner>/sddp-<your-service>` (staging) and
     `…/sddp-registry/sddp-<your-service>` (production),
   - the config-repo bump path → `manifests/<your-service>/deployment.yaml`.
   Nothing is hard-coded and there is **no init step to run** — the workflows are
   already generic, so the CI gate is green on the sample app immediately.

That's it for the service side. What's left is the platform wire-up below (done
once per service, by a platform maintainer).

> **Why `sddp-<service>`?** The `sddp-` prefix is stripped to form the slug used
> for the `manifests/<slug>/` path, and the full repo name is the image name. Keep
> the prefix so the two line up.

---

## 2. Wire-up (per service, by a platform maintainer)

The pipeline is generic; these four steps connect *your* service to the platform.

### a. Per-org secrets the pipeline needs
Set these as **repository secrets** on this repo (an organization can set them once
at the org level and let every repo inherit; a personal account sets them per repo):

| Secret | Used by | What it is |
|--------|---------|------------|
| `NVD_API_KEY` | CI (SCA) | An NVD API key so Dependency-Check syncs at usable speed. |
| `DOCR_TOKEN` | release | DigitalOcean API token with registry read+create+update (no delete). Used as both username and password for the production registry. |
| `CONFIG_BOT_APP_ID` | release | App ID of the GitHub App that opens the config-bump PR. |
| `CONFIG_BOT_PRIVATE_KEY` | release | That App's private key. The App must be installed on the **config repo** (`sddp-app-config`) with contents + pull-requests write. |

`GITHUB_TOKEN` (for GHCR staging pushes) is provided automatically — no setup.

> **Tip:** these four values are identical for every service (same owner, same App,
> same registry). Keep them in your secret manager as the single source of truth and
> sync them into each repo, rather than pasting values by hand.

> **GHCR note:** if a staging package of the same name already exists from another
> repo, grant this repo **Write** access to that package (its Actions access
> settings), or the first staging push is denied.

### b. Trust this service's signer
The release signs with this repo's own keyless OIDC identity:

```
issuer:  https://token.actions.githubusercontent.com
subject: https://github.com/<owner>/sddp-<your-service>/.github/workflows/release.yml@refs/heads/main
```

Add **that exact subject** to the platform's trusted-signer allowlist and make
sure the admission policy is enforcing **before** merging the first config-bump PR
— otherwise admission is fail-closed and rejects the new signer's digest. Keep it
an explicit entry, never a loose wildcard.

### c. Delivery manifests in the config repo
Add this service's Deployment + Service (and Ingress, if public) under
`manifests/<your-service>/` in the project config repo (`sddp-app-config`), plus
the network-policy allow-rules for its tier on the default-deny floor. The release
pipeline's bump job edits `manifests/<your-service>/deployment.yaml` — that path
must exist for the first bump to land.

### d. Required-checks ruleset
In this repo, add a branch-protection ruleset on `main` requiring these checks
(the CI job names) plus at least one review:

- `Secret scan (Gitleaks)`
- `SAST (Semgrep)`
- `SCA — Dependency-Check`
- `Dockerfile lint — Hadolint`
- `Build + scan + publish — Trivy`

---

## 3. The loop, once wired

```
push branch → PR → CI gate (all checks green) → human review → merge
   → release: SBOM + keyless sign + promote to prod registry
   → auto-PR bumps the digest in the config repo
   → human merges the bump → Argo CD syncs → admission verifies the signature → live
```

Every merge to `main` re-signs and re-promotes; the config bump is the only
cross-repo write, and a human gates both the code merge and the deploy merge.

---

## 4. Local development

```bash
npm install          # regenerate package-lock.json if you change deps (commit it)
npm start            # serves on :3000 — GET / and /health
```

Build and run the container (runs as a non-root user by default):

```bash
docker build -t sddp-service:dev .
docker run --rm -p 3000:3000 sddp-service:dev
```

## 5. Secret scanning (pre-commit)

A local Gitleaks pre-commit hook catches secrets **before** they enter Git
history. Install it once per clone:

```bash
brew install pre-commit      # or: pipx install pre-commit
pre-commit install
```

This layer is bypassable (`--no-verify`); the enforceable backstop is the CI
secret scan on every pull request.
