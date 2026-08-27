#!/usr/bin/env bash
# clean-homebrew.sh — clear Homebrew's download cache and old
# formula/cask versions. Dry-run by default.
#
# Usage: ./clean-homebrew.sh [--yes]
#   --yes   actually delete (default: dry-run, uses `brew cleanup --dry-run`)

set -euo pipefail

DRY_RUN=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y) DRY_RUN=0 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if ! command -v brew >/dev/null 2>&1; then
  echo "brew not found — nothing to do."
  exit 0
fi

echo "Mode: $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN (pass --yes to actually clean)' || echo 'LIVE — cleaning')"
echo

if [[ $DRY_RUN -eq 1 ]]; then
  brew cleanup --dry-run
else
  brew cleanup
fi

echo
CACHE_DIR=$(brew --cache 2>/dev/null || true)
if [[ -n "$CACHE_DIR" && -d "$CACHE_DIR" ]]; then
  echo "Homebrew cache dir: $CACHE_DIR ($(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}' || true))"
fi

echo
echo "Done."
[[ $DRY_RUN -eq 1 ]] && echo "This was a dry run — rerun with --yes to actually clean."
