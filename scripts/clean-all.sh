#!/usr/bin/env bash
# clean-all.sh — orchestrates clean-caches.sh, clean-xcode.sh,
# clean-docker.sh, and clean-homebrew.sh. Dry-run by default, passes
# --yes through to each. Does NOT touch the Trash (run empty-trash.sh
# separately — it's irreversible, so it stays opt-in on its own).
#
# Usage: ./clean-all.sh [--yes]
#   --yes   actually clean everything (default: dry-run report only)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

YES_FLAG=()
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES_FLAG=(--yes) ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ ${#YES_FLAG[@]} -eq 0 ]]; then
  echo "=============================================="
  echo " DRY RUN — nothing will be deleted."
  echo " Rerun with --yes to actually clean."
  echo "=============================================="
fi
echo

section() { printf '\n\033[1m>>> %s\033[0m\n' "$1"; }

section "Caches (npm/yarn/pnpm/pip + ~/Library/Caches)"
"$DIR/clean-caches.sh" "${YES_FLAG[@]}"

section "Xcode (DerivedData, simulators, old DeviceSupport)"
"$DIR/clean-xcode.sh" "${YES_FLAG[@]}"

section "Docker (containers, dangling images, build cache)"
"$DIR/clean-docker.sh" "${YES_FLAG[@]}"

section "Homebrew (cleanup old versions/downloads)"
"$DIR/clean-homebrew.sh" "${YES_FLAG[@]}"

section "Done"
echo "Not run automatically (do these separately when ready):"
echo "  ./empty-trash.sh          — empty ~/.Trash (irreversible)"
echo "  ./find-large-files.sh     — hunt individual large files"
echo "  ./find-node-modules.sh    — hunt stale node_modules dirs"
echo
echo "Run ./analyze-disk.sh again to see how much space was reclaimed."
