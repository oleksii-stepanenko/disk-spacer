#!/usr/bin/env bash
# find-node-modules.sh — locate every node_modules directory under a root
# and report its size, sorted largest-first. Report-only; never deletes.
#
# Usage: ./find-node-modules.sh [-p PATH]
#   -p PATH   root to search (default: $HOME)
#
# To actually remove one after reviewing:
#   rm -rf "/path/to/project/node_modules"   # regenerate with npm/yarn/pnpm install

set -euo pipefail

ROOT="$HOME"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) ROOT="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "Searching under $ROOT for node_modules directories ..."
echo

# Prune nested node_modules so we don't double-report vendored subtrees.
find "$ROOT" -xdev -type d -name node_modules -prune -exec du -sh {} + 2>/dev/null \
  | sort -rh || true

echo
echo "Review before deleting. A directory only unused by a project you're not"
echo "actively working on is a good candidate; run the project's install"
echo "command again if you need it back."
