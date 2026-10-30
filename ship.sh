#!/bin/bash
# Pushes the site (Vercel) and builds new installers (GitHub) with the next version number.
set -e
cd "$(dirname "$0")"
git add -A
git commit -m "${1:-Update}" || true
git push
last=$(git tag --list 'v*' --sort=-v:refname | head -n1)
last=${last:-v0.0.0}
IFS=. read -r a b c <<< "${last#v}"
new="v$a.$b.$((c+1))"
git tag "$new"
git push origin "$new"
echo "Done. Site updating, installers building as $new"
