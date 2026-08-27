#!/usr/bin/env bash
# analyze-disk.sh — coarse disk usage report: overall free space, biggest
# top-level dirs under $HOME and ~/Library.
#
# Usage: ./analyze-disk.sh [-n COUNT]
#   -n COUNT   how many entries to show per section (default 15)

set -euo pipefail

COUNT=15
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) COUNT="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "Overall disk usage"
df -H / | awk 'NR==1 || NR==2'

section "Top $COUNT largest items directly under \$HOME ($HOME)"
du -sh "$HOME"/* "$HOME"/.[^.]* 2>/dev/null | sort -rh | head -n "$COUNT" || true

if [[ -d "$HOME/Library" ]]; then
  section "Top $COUNT largest items under ~/Library"
  du -sh "$HOME/Library"/* 2>/dev/null | sort -rh | head -n "$COUNT" || true
fi

if [[ -d "$HOME/Library/Caches" ]]; then
  section "Top $COUNT largest items under ~/Library/Caches"
  du -sh "$HOME/Library/Caches"/* 2>/dev/null | sort -rh | head -n "$COUNT" || true
fi

section "Local Time Machine snapshots (purgeable, macOS reclaims automatically)"
tmutil listlocalsnapshots / 2>/dev/null || echo "  (none, or tmutil unavailable)"

echo
echo "Tip: for a per-file breakdown use ./find-large-files.sh, or 'brew install ncdu' for an interactive explorer."
