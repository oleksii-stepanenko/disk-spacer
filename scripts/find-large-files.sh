#!/usr/bin/env bash
# find-large-files.sh — find individual files above a size threshold,
# sorted largest-first. Report-only; never deletes anything.
#
# Usage: ./find-large-files.sh [-s SIZE] [-p PATH] [-n COUNT]
#   -s SIZE    minimum size, find(1) syntax (default +500M)
#   -p PATH    root to search (default: $HOME)
#   -n COUNT   max results to show (default 50)

set -euo pipefail

SIZE="+500M"
ROOT="$HOME"
COUNT=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SIZE="$2"; shift 2 ;;
    -p) ROOT="$2"; shift 2 ;;
    -n) COUNT="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "Searching under $ROOT for files >= ${SIZE#+} ..."
echo "(this can take a while on large home directories)"
echo

# -x stays on one filesystem so we don't wander into mounted volumes/network shares.
find "$ROOT" -xdev -type f -size "$SIZE" -not -path '*/.Trash/*' \
  -exec du -h {} + 2>/dev/null \
  | sort -rh \
  | head -n "$COUNT" || true

echo
echo "Review before deleting — nothing above was removed."
