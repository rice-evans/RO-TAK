#!/bin/bash
set -e
cd "$(dirname "$0")"
release=0
if [ "$1" = "-r" ]; then release=1; shift; fi
d=$(date +%-d)
case $d in 1|21|31) s=st;; 2|22) s=nd;; 3|23) s=rd;; *) s=th;; esac
perl -pi -e "s/Updated on \d+(st|nd|rd|th) \w+ \d{4}/Updated on $d$s $(date +%B) $(date +%Y)/" index.html
perl -MPOSIX -pi -e 'BEGIN { $e = strftime("%Y-%m-%dT00:00:00Z", gmtime(time + 86400 * 364)) } s/^Expires: .*/Expires: $e/' .well-known/security.txt
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
