#!/usr/bin/env bash
# clean-docker.sh — prune stopped containers, dangling images, unused
# networks/volumes, and the build cache. Dry-run by default (shows `docker
# system df` and what commands would run, but doesn't run the prune).
#
# Usage: ./clean-docker.sh [--yes] [--all]
#   --yes    actually prune (default: dry-run)
#   --all    also remove ALL unused images (not just dangling ones) and
#            unused volumes — more aggressive, use with care

set -euo pipefail

DRY_RUN=1
ALL=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) DRY_RUN=0 ;;
    --all) ALL=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found — nothing to do."
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon isn't running (Docker Desktop not started?) — skipping."
  exit 0
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    eval "$@"
  fi
}

echo "Mode: $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN (pass --yes to actually prune)' || echo 'LIVE — pruning')"
echo

echo "Current Docker disk usage:"
docker system df
echo

if [[ $ALL -eq 1 ]]; then
  echo "Aggressive mode: removing ALL unused images and volumes, not just dangling."
  run "docker system prune -a --volumes -f"
else
  run "docker container prune -f"
  run "docker image prune -f"
  run "docker builder prune -f"
  echo
  echo "(Unused-but-tagged images and volumes were left alone — rerun with --all"
  echo " to also remove those. Volumes can hold data you still want.)"
fi

echo
echo "Done."
[[ $DRY_RUN -eq 1 ]] && echo "This was a dry run — rerun with --yes to actually prune."
