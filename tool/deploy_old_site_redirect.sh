#!/usr/bin/env bash
# Replaces the old web address (https://epicultrakingsmizzy.github.io/Michikub/, this repo's
# gh-pages branch) with a page that forwards to https://playmichikub.github.io/, keeping ?join=CODE.
# One-off; tool/deploy_web.sh publishes the game itself.
set -euo pipefail
cd "$(dirname "$0")/.."
remote=$(git remote get-url origin)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp tool/old_site/index.html tool/old_site/404.html "$tmp/"
touch "$tmp/.nojekyll"
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$OLDPWD" config user.name || echo deploy)" \
    -c user.email="$(git -C "$OLDPWD" config user.email || echo deploy@localhost)" \
    commit -q -m "Michikub moved to https://playmichikub.github.io/"
git push -q --force "$remote" gh-pages:gh-pages
echo "Old address now forwards to https://playmichikub.github.io/"
