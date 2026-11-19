#!/usr/bin/env bash
# Builds the web version and publishes it to GitHub Pages at the root of
# https://playmichikub.github.io/ (the PlayMichikub/PlayMichikub.github.io repo, which holds only
# the built files; the source stays here).
#
#   tool/deploy_web.sh
#
# The site repo's main branch is a single commit of the build that each deploy replaces.
# It includes /.well-known/assetlinks.json (from web/), which lets Android open join links in the
# app (App Links), and .nojekyll so GitHub serves the dot folder.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f /home/box/dev/env.sh ] && source /home/box/dev/env.sh

site=https://github.com/PlayMichikub/PlayMichikub.github.io.git

flutter build web --release --base-href /
touch build/web/.nojekyll
mkdir -p build/web/.well-known
cp web/.well-known/assetlinks.json build/web/.well-known/assetlinks.json

src=$(git rev-parse --short HEAD)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r build/web/. "$tmp/"
cd "$tmp"
git init -q -b main
git add -A
git -c user.name="$(git -C "$OLDPWD" config user.name || echo deploy)" \
    -c user.email="$(git -C "$OLDPWD" config user.email || echo deploy@localhost)" \
    commit -q -m "Web build of Michikub $src"
git push -q --force "$site" main:main
echo "Deployed web build of $src to https://playmichikub.github.io/"
