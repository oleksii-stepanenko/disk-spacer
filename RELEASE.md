# Releasing Disk Spacer

Exact commands, in order. Run them from the repo root.

---

## One time only

```sh
./scripts/setup-release.sh
```

That script:

1. copies `packaging/homebrew/disk-spacer.rb` into your `homebrew-tap`
   (the release workflow only *updates* the cask — it cannot create it)
2. creates a self-signed code-signing certificate and uploads it as
   `SIGNING_CERTIFICATE_P12` / `SIGNING_CERTIFICATE_PASSWORD`
3. asks for a personal access token and uploads it as `TAP_GITHUB_TOKEN`

It is safe to re-run — anything already done is skipped. It never replaces an
existing signing certificate, because that would reset every user's Full Disk
Access grant.

You will be asked for a token in step 3. Create one at
**https://github.com/settings/personal-access-tokens/new** with
**Contents: Read and write** on `homebrew-tap` only.

---

## Before the first tag: dry run

This has never been built on GitHub's runner. Everything so far was verified
locally on Swift 6.3, but `macos-15` runners ship an older toolchain — worth
proving before a tag exists.

```sh
gh workflow run "Build & Release" --ref main

gh run watch "$(gh run list --workflow='Build & Release' --limit 1 --json databaseId --jq '.[0].databaseId')"
```

A manual run is free: the version resolves to `0.0.0`, and both "Attach to
Release" and "Bump Homebrew cask" are gated on a tag, so nothing public is
created. You still get a downloadable `DiskSpacer.dmg` artifact to open and
check.

If it fails, fix it and re-run before continuing.

---

## Publish a release

```sh
git tag v1.0.0
git push origin v1.0.0
```

Watch it:

```sh
gh run watch "$(gh run list --workflow='Build & Release' --limit 1 --json databaseId --jq '.[0].databaseId')"
```

That builds the app, runs the tests, signs it, packages `DiskSpacer.dmg`,
attaches it to a GitHub Release, and bumps the cask in your tap.

---

## Check it worked

```sh
gh release view v1.0.0
brew update
brew install --cask oleksii-stepanenko/tap/disk-spacer
```

---

## Later releases

Just tag again — setup is already done:

```sh
git tag v1.0.1
git push origin v1.0.1
```

---

## If something breaks

**Cask bump fails with "not found in the tap"**
`Casks/disk-spacer.rb` is missing. Re-run `./scripts/setup-release.sh`.

**Cask bump is skipped with a notice**
`TAP_GITHUB_TOKEN` is not set, or it expired. Re-run the setup script.

**`brew install` fails with a checksum mismatch**
The cask is still on its placeholder `sha256`, meaning the bump never ran.
Check the "Bump Homebrew cask" step in the release run.

**Build fails with "Designated requirement is cdhash-based"**
The certificate did not get applied. The signing secrets are wrong or missing
— re-run the setup script and answer yes to creating a certificate.

**Pages deploy fails**
Trigger a *fresh* run rather than re-running the failed one. Re-running only
the failed job uploads a second artifact into the same run, and the deploy
then refuses with "Multiple artifacts named github-pages".

```sh
gh workflow run "Deploy landing page" --ref main
```

---

## Keep this safe

`~/.disk-spacer-signing/` holds a backup of your signing certificate.

macOS ties the Full Disk Access permission to the app's signature. Sign every
release with the same certificate and users grant permission once. Lose it and
sign with a new one, and macOS treats the app as a different app — every user
has to grant Full Disk Access again.
