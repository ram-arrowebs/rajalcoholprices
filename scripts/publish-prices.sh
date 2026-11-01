#!/usr/bin/env bash
# Fetch the current price list from this machine and push it to main,
# doing by hand what the scheduled workflow does. Use it from India when
# GitHub-hosted runners cannot reach the IEMS host.
#
# Safe to run from any branch: it works in a throwaway worktree of
# origin/main and never touches your checkout or local data/.
#
# Environment:
#   REMOTE  git remote to push to (default: origin)
#   BRANCH  branch GitHub Pages serves (default: main)
set -euo pipefail

top="$(git rev-parse --show-toplevel)"
remote="${REMOTE:-origin}"
branch="${BRANCH:-main}"

git -C "$top" fetch --quiet "$remote" "$branch"

wt="$(mktemp -d)"
trap 'git -C "$top" worktree remove --force "$wt" 2> /dev/null || true' EXIT
git -C "$top" worktree add --quiet --detach "$wt" "$remote/$branch"

DATA_DIR="$wt/data" "$top/scripts/fetch-prices.sh"

# data/ is gitignored for local development; force-add here.
git -C "$wt" add -f data/prices.json data/meta.json
if git -C "$wt" diff --cached --quiet -- data/prices.json; then
  echo "Price data unchanged; nothing to push."
  exit 0
fi
git -C "$wt" commit --quiet -m "chore(data): update price list $(date -u +%Y-%m-%d)"
git -C "$wt" push --quiet "$remote" "HEAD:$branch"
echo "Pushed updated price list to $remote/$branch."
