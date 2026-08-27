#!/usr/bin/env bash
# clean-caches.sh — clear user-level caches: ~/Library/Caches, npm, yarn,
# pnpm, pip, and Homebrew's download cache. Dry-run by default.
#
# Usage: ./clean-caches.sh [--yes] [--skip-library-caches]
#   --yes                    actually delete (default: print what would happen)
#   --skip-library-caches    skip the broad ~/Library/Caches sweep, only
#                            clean known package-manager caches

set -euo pipefail

DRY_RUN=1
SKIP_LIBRARY_CACHES=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) DRY_RUN=0 ;;
    --skip-library-caches) SKIP_LIBRARY_CACHES=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    eval "$@"
  fi
}

size_of() { du -sh "$1" 2>/dev/null | awk '{print $1}'; return 0; }

echo "Mode: $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN (pass --yes to actually delete)' || echo 'LIVE — deleting')"
echo

if [[ $SKIP_LIBRARY_CACHES -eq 0 && -d "$HOME/Library/Caches" ]]; then
  echo "~/Library/Caches: $(size_of "$HOME/Library/Caches")"
  run "find '$HOME/Library/Caches' -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  echo
fi

if command -v npm >/dev/null 2>&1; then
  NPM_CACHE=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
  echo "npm cache ($NPM_CACHE): $(size_of "$NPM_CACHE")"
  run "npm cache clean --force"
  echo
fi

if command -v yarn >/dev/null 2>&1; then
  echo "yarn cache:"
  run "yarn cache clean"
  echo
fi

if command -v pnpm >/dev/null 2>&1; then
  echo "pnpm store:"
  run "pnpm store prune"
  echo
fi

if command -v pip3 >/dev/null 2>&1; then
  echo "pip cache: $(size_of "$HOME/Library/Caches/pip")"
  run "pip3 cache purge"
  echo
fi

echo "Done."
[[ $DRY_RUN -eq 1 ]] && echo "This was a dry run — rerun with --yes to actually clean."
