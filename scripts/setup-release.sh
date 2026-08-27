#!/usr/bin/env bash
# setup-release.sh — one-time setup so `git tag` publishes a release and
# updates the Homebrew cask automatically.
#
# Run it once. It is idempotent: re-running skips anything already done.
#
#   ./scripts/setup-release.sh
#
# It does four things:
#   1. copies the cask into your homebrew-tap (the release only *updates* it)
#   2. creates a self-signed code-signing certificate
#   3. uploads the signing + tap secrets to the disk-spacer repo
#   4. tells you what to run next
#
# Nothing here touches the disk-spacer repo's code or history.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_USER="oleksii-stepanenko"
APP_REPO="$GH_USER/disk-spacer"
TAP_REPO="$GH_USER/homebrew-tap"
CASK_SRC="$ROOT/packaging/homebrew/disk-spacer.rb"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────
step "Checking prerequisites"

command -v gh >/dev/null || { echo "gh CLI not found: brew install gh"; exit 1; }
command -v openssl >/dev/null || { echo "openssl not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in: gh auth login"; exit 1; }
ok "gh CLI authenticated as $(gh api user --jq .login)"

[[ -f "$CASK_SRC" ]] || { echo "Missing $CASK_SRC"; exit 1; }
ok "cask template found"

# ── 1. Cask into the tap ─────────────────────────────────────────────────────
step "1. Homebrew cask"

if gh api "repos/$TAP_REPO/contents/Casks/disk-spacer.rb" >/dev/null 2>&1; then
  ok "Casks/disk-spacer.rb already exists in $TAP_REPO"
else
  warn "Casks/disk-spacer.rb is missing from $TAP_REPO"
  echo "     The release workflow only *updates* the cask — it cannot create it,"
  echo "     so this has to be added once before the first tag."
  read -r -p "     Add it now? [y/N] " reply
  if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
    TMP="$(mktemp -d)"
    git clone -q "https://github.com/$TAP_REPO.git" "$TMP/tap"
    mkdir -p "$TMP/tap/Casks"
    cp "$CASK_SRC" "$TMP/tap/Casks/disk-spacer.rb"
    (
      cd "$TMP/tap"
      git add Casks/disk-spacer.rb
      git commit -qm "Add disk-spacer cask"
      git push -q
    )
    rm -rf "$TMP"
    ok "cask pushed to $TAP_REPO"
  else
    warn "skipped — brew install will not work until this is done"
  fi
fi

# ── 2. Signing certificate ───────────────────────────────────────────────────
step "2. Code-signing certificate"

echo "     Disk Spacer asks for Full Disk Access. macOS ties that permission to"
echo "     the app's signature. Signing every release with the SAME self-signed"
echo "     certificate means users grant it once; ad-hoc signing means they must"
echo "     re-grant it after every single update."
echo

if gh secret list --repo "$APP_REPO" 2>/dev/null | grep -q SIGNING_CERTIFICATE_P12; then
  ok "SIGNING_CERTIFICATE_P12 already set — leaving it alone"
  echo "     (Replacing it would reset everyone's Full Disk Access grant.)"
else
  # Reusing a certificate you already own is fine: a code-signing certificate
  # is not tied to a bundle id. The designated requirement pins the identifier
  # *and* the certificate, so two apps signed with one certificate stay
  # separate as far as macOS permissions are concerned.
  REUSE_P12=""
  REUSE_PWD_FILE=""
  for candidate in \
      "$HOME/.showpoint-signing/showpoint-signing.p12" \
      "$HOME/.disk-spacer-signing/cert.p12"; do
    if [[ -f "$candidate" ]]; then
      dir="$(dirname "$candidate")"
      pwdfile="$(ls "$dir"/*password*.txt 2>/dev/null | head -1 || true)"
      [[ -n "$pwdfile" ]] && { REUSE_P12="$candidate"; REUSE_PWD_FILE="$pwdfile"; break; }
    fi
  done

  if [[ -n "$REUSE_P12" ]]; then
    subject="$(openssl pkcs12 -in "$REUSE_P12" -nokeys -passin "file:$REUSE_PWD_FILE" -legacy 2>/dev/null \
               | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject=//')"
    echo "     Found a certificate you already use:"
    echo "       $REUSE_P12"
    echo "       $subject"
    echo
    echo "     Reusing it is safe — the app identifier keeps the two apps'"
    echo "     permissions separate. It also means one certificate to back up."
    echo "     The only visible difference: Disk Spacer's signing authority will"
    echo "     read as that certificate's name rather than its own."
    read -r -p "     Reuse it? [Y/n] " reply
  else
    reply="new"
  fi

  if [[ "$reply" != "n" && "$reply" != "N" && -n "$REUSE_P12" ]]; then
    base64 -i "$REUSE_P12" | gh secret set SIGNING_CERTIFICATE_P12 --repo "$APP_REPO"
    tr -d '\n' < "$REUSE_PWD_FILE" | gh secret set SIGNING_CERTIFICATE_PASSWORD --repo "$APP_REPO"
    ok "reused $(basename "$REUSE_P12") — uploaded to $APP_REPO"
    echo "     Keep backing up $(dirname "$REUSE_P12") — it now signs two apps."
    SKIP_NEW_CERT=1
  fi

  if [[ "${SKIP_NEW_CERT:-0}" == "1" ]]; then
    :
  else
  read -r -p "     Create a NEW signing certificate and upload it? [Y/n] " reply
  if [[ "$reply" == "n" || "$reply" == "N" ]]; then
    warn "skipped — releases will be ad-hoc signed"
  else
    CERTDIR="$(mktemp -d)"
    # A random password; it only protects the .p12 in transit to GitHub.
    P12_PWD="$(openssl rand -base64 24)"

    cat > "$CERTDIR/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[dn]
CN = Disk Spacer Self-Signed
O  = Disk Spacer
C  = US

[v3]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
      -config "$CERTDIR/cert.cnf" 2>/dev/null

    openssl pkcs12 -export -legacy \
      -out "$CERTDIR/cert.p12" \
      -inkey "$CERTDIR/key.pem" -in "$CERTDIR/cert.pem" \
      -passout "pass:$P12_PWD" 2>/dev/null

    base64 -i "$CERTDIR/cert.p12" | gh secret set SIGNING_CERTIFICATE_P12 --repo "$APP_REPO"
    printf '%s' "$P12_PWD" | gh secret set SIGNING_CERTIFICATE_PASSWORD --repo "$APP_REPO"
    ok "certificate created and uploaded"

    # Keep a local backup — losing this means future updates get a different
    # identity, and every user has to re-grant Full Disk Access.
    BACKUP="$HOME/.disk-spacer-signing"
    mkdir -p "$BACKUP"
    cp "$CERTDIR/cert.p12" "$BACKUP/cert.p12"
    printf '%s\n' "$P12_PWD" > "$BACKUP/password.txt"
    chmod 700 "$BACKUP"; chmod 600 "$BACKUP"/*
    ok "backup saved to $BACKUP  (keep this — see note below)"
    rm -rf "$CERTDIR"
  fi
  fi
fi

# ── 3. Tap token ─────────────────────────────────────────────────────────────
step "3. Token for updating the tap"

if gh secret list --repo "$APP_REPO" 2>/dev/null | grep -q TAP_GITHUB_TOKEN; then
  ok "TAP_GITHUB_TOKEN already set"
else
  echo "     Releases live in $APP_REPO but the cask lives in $TAP_REPO."
  echo "     A workflow's built-in token only reaches its own repo, so bumping"
  echo "     the cask needs a personal access token with write access to the tap."
  echo
  echo "     Create one here (Contents: Read and write, on homebrew-tap):"
  echo "       https://github.com/settings/personal-access-tokens/new"
  echo
  read -r -s -p "     Paste the token (input hidden, blank to skip): " TOKEN
  echo
  if [[ -n "$TOKEN" ]]; then
    printf '%s' "$TOKEN" | gh secret set TAP_GITHUB_TOKEN --repo "$APP_REPO"
    ok "TAP_GITHUB_TOKEN set"
  else
    warn "skipped — the cask will not auto-update on release"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
step "Current state"
gh secret list --repo "$APP_REPO" 2>/dev/null | sed 's/^/  /' || echo "  (none)"

step "Next"
cat <<'NEXT'
  1. Dry run — proves the app builds on GitHub's runner. Creates nothing public:

       gh workflow run "Build & Release" --ref main
       gh run watch "$(gh run list --workflow='Build & Release' --limit 1 --json databaseId --jq '.[0].databaseId')"

  2. If that passes, publish:

       git tag v1.0.0
       git push origin v1.0.0

  3. Once the run finishes:

       brew install --cask oleksii-stepanenko/tap/disk-spacer
NEXT

cat <<'NOTE'

  Note on the signing certificate backup in ~/.disk-spacer-signing:
  keep it. If you ever rebuild the secrets from a different certificate, macOS
  treats the app as a new one and every user has to grant Full Disk Access
  again. Same certificate = permission survives updates.
NOTE
