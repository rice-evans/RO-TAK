#!/bin/bash
set -e
cd "$(dirname "$0")"
release=0
if [ "$1" = "-r" ]; then release=1; shift; fi
git add -A
git commit -m "${1:-Update}" || true
git push
if [ "$release" = "1" ]; then
  last=$(git tag --list 'v*' --sort=-v:refname | head -n1)
  last=${last:-v0.0.0}
  IFS=. read -r a b c <<< "${last#v}"
  new="v$a.$b.$((c+1))"
  git tag "$new"
  git push origin "$new"
  echo "Done. Site updating, installers building as $new"
else
  echo "Done. Site updating. No release drafted. Use -r to build a release."
fi
