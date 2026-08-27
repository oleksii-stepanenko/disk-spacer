# Publishing Disk Spacer

One-time setup, then every release is automatic.

## 1. Add the cask to your tap (once, before the first tag)

The release workflow **updates** the cask, it does not create it. Copy this
file into your tap repository once:

```sh
git clone https://github.com/oleksii-stepanenko/homebrew-tap.git
cp packaging/homebrew/disk-spacer.rb homebrew-tap/Casks/disk-spacer.rb
cd homebrew-tap
git add Casks/disk-spacer.rb
git commit -m "Add disk-spacer cask"
git push
```

The placeholder `version` and `sha256` in it are fine — the first release
overwrites both.

## 2. Add repository secrets

In **disk-spacer → Settings → Secrets and variables → Actions**:

| Secret | What it does | Required? |
|---|---|---|
| `TAP_GITHUB_TOKEN` | A PAT with write access to `homebrew-tap`, so the release can bump the cask. | Needed for automatic `brew` updates |
| `SIGNING_CERTIFICATE_P12` | Base64 of a self-signed code-signing `.p12`. | Strongly recommended — see below |
| `SIGNING_CERTIFICATE_PASSWORD` | The password for that `.p12`. | With the above |

Without `TAP_GITHUB_TOKEN` the cask bump is skipped (with a notice, not a
failure). Without the signing secrets the app is ad-hoc signed and still works.

### Why signing matters here

Disk Spacer asks for **Full Disk Access**. macOS ties that grant to the app's
code signature.

- **Ad-hoc signed** (`--sign -`): the signature changes on every build, so
  macOS treats each update as a different app. Users must re-grant Full Disk
  Access after *every* update.
- **Signed with a stable self-signed certificate**: the signature is tied to
  the certificate, not the build, so the grant survives updates. Users grant
  it once.

The workflow checks this and fails the build if the designated requirement
came out `cdhash`-based, which would mean the certificate was not applied.

## 3. Enable GitHub Pages (once)

**Settings → Pages → Build and deployment → Source: GitHub Actions.**

The landing page then deploys from `docs/` on every push to `main`.

## 4. Release

```sh
git tag v1.0.0
git push origin v1.0.0
```

That builds the app, runs the tests, signs it, packages `DiskSpacer.dmg`,
attaches it to a GitHub Release, and bumps the cask.

Then:

```sh
brew install --cask oleksii-stepanenko/tap/disk-spacer
```

## Names that must stay in sync

If you rename anything, these four must match, or `brew install` breaks:

| Thing | Value | Set in |
|---|---|---|
| DMG filename | `DiskSpacer.dmg` | `release.yml` and the cask `url` |
| App bundle name | `Disk Spacer.app` | `make-app.sh` and the cask `app` stanza |
| Bundle identifier | `io.stepanenko.DiskSpacer` | `make-app.sh` and the cask `zap` paths |
| Cask filename | `Casks/disk-spacer.rb` | the tap, and the bump step in `release.yml` |
