#!/usr/bin/env bash
# empty-trash.sh — empty ~/.Trash. Irreversible, so this always asks for
# interactive confirmation (typing "yes") unless --yes is passed AND
# --force is also passed, to make scripted/unattended use an explicit choice.
#
# Usage: ./empty-trash.sh [--yes] [--force]
#   --yes     skip the interactive prompt (still requires --force to run
#             fully unattended with no confirmation at all)
#   --force   combined with --yes, actually empties with zero prompts —
#             intended for use from clean-all.sh --yes, not for casual use

set -euo pipefail

SKIP_PROMPT=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) SKIP_PROMPT=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

TRASH="$HOME/.Trash"
if [[ ! -d "$TRASH" ]]; then
  echo "No ~/.Trash directory found."
  exit 0
fi

SIZE=$(du -sh "$TRASH" 2>/dev/null | awk '{print $1}' || true)
echo "~/.Trash currently uses: ${SIZE:-0B}"

if [[ $SKIP_PROMPT -eq 1 && $FORCE -eq 1 ]]; then
  : # proceed without prompting
elif [[ $SKIP_PROMPT -eq 1 ]]; then
  read -r -p "This permanently deletes everything in ~/.Trash. Type 'yes' to continue: " reply
  [[ "$reply" == "yes" ]] || { echo "Aborted."; exit 1; }
else
  echo "Dry run: would permanently delete everything in $TRASH."
  echo "Rerun with --yes to be prompted, or --yes --force to skip the prompt."
  exit 0
fi

rm -rf "${TRASH:?}"/*
echo "Trash emptied."
