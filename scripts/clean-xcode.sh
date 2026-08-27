#!/usr/bin/env bash
# clean-xcode.sh — clear Xcode build artifacts: DerivedData, unavailable
# simulator devices, and old iOS DeviceSupport folders. Dry-run by default.
#
# Usage: ./clean-xcode.sh [--yes] [--keep-device-support N]
#   --yes                       actually delete (default: dry-run)
#   --keep-device-support N     keep the N most recently modified
#                                DeviceSupport folders (default 3)

set -euo pipefail

DRY_RUN=1
KEEP=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) DRY_RUN=0; shift ;;
    --keep-device-support) KEEP="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
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

DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -d "$DERIVED" ]]; then
  echo "DerivedData ($DERIVED): $(size_of "$DERIVED")"
  run "rm -rf '$DERIVED'/*"
  echo
fi

if command -v xcrun >/dev/null 2>&1; then
  echo "Unavailable simulator devices:"
  run "xcrun simctl delete unavailable"
  echo
else
  echo "xcrun not found — skipping simulator cleanup."
  echo
fi

DEVSUPPORT="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
if [[ -d "$DEVSUPPORT" ]]; then
  echo "iOS DeviceSupport ($DEVSUPPORT): $(size_of "$DEVSUPPORT")"
  echo "Keeping the $KEEP most recently used, removing the rest:"
  # List oldest-first, drop the last $KEEP (most recent), delete the remainder.
  # (Avoids `mapfile`, which isn't available in macOS's stock bash 3.2.)
  FOUND_OLD=0
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    FOUND_OLD=1
    run "rm -rf '$DEVSUPPORT/$d'"
  done < <(ls -1t "$DEVSUPPORT" | tail -n +"$((KEEP + 1))")
  [[ $FOUND_OLD -eq 0 ]] && echo "  nothing to remove (fewer than $KEEP folders present)"
  echo
fi

ARCHIVES="$HOME/Library/Developer/Xcode/Archives"
if [[ -d "$ARCHIVES" ]]; then
  echo "Archives ($ARCHIVES): $(size_of "$ARCHIVES")"
  echo "  Not auto-deleted — these are your app upload/export archives."
  echo "  Review manually: open '$ARCHIVES' (or Xcode → Window → Organizer)."
  echo
fi

echo "Done."
[[ $DRY_RUN -eq 1 ]] && echo "This was a dry run — rerun with --yes to actually clean."
