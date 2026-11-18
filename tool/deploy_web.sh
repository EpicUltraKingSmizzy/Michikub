#!/usr/bin/env bash
# Builds the web version and publishes it to GitHub Pages (the gh-pages branch):
# https://epicultrakingsmizzy.github.io/Michikub/
#
#   tool/deploy_web.sh
#
# gh-pages holds only the built files, as a single commit that each deploy replaces.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f /home/box/dev/env.sh ] && source /home/box/dev/env.sh

flutter build web --release --base-href /Michikub/
touch build/web/.nojekyll

remote=$(git remote get-url origin)
src=$(git rev-parse --short HEAD)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r build/web/. "$tmp/"
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$OLDPWD" config user.name || echo deploy)" \
    -c user.email="$(git -C "$OLDPWD" config user.email || echo deploy@localhost)" \
    commit -q -m "Web build of $src"
git push -q --force "$remote" gh-pages:gh-pages
echo "Deployed web build of $src to gh-pages."
