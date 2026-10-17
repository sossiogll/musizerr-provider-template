#!/bin/sh
# Check that a change of the provider raises its version: the CI job "provider version", on every pull request into dev.
#
#   scripts/version-check.sh <base> [<head>]
#
#   <base>  the commit the change is compared with (in CI the first parent of the pull request's merge commit: dev)
#   <head>  the changed commit (default HEAD)
#
# Any changed file outside .github/, scripts/, README.md, LICENSE, .gitignore and catalog.json is a change of the
# provider, and then `version` in pyproject.toml must be greater than on <base>: that version is the tag of its image,
# and the image of a version that is not published yet is published when the change reaches dev
# (.github/workflows/publish.yml). Versions are compared as `sort -V` does (1.10.0 is greater than 1.9.0). The exit
# status is non-zero if the provider needs a new version.
set -eu

[ $# -ge 1 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
BASE=$1
HEAD=${2:-HEAD}
git rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "$BASE is not a commit" >&2; exit 2; }
git rev-parse -q --verify "$HEAD^{commit}" >/dev/null || { echo "$HEAD is not a commit" >&2; exit 2; }

version_at() { git show "$1:pyproject.toml" 2>/dev/null | sed -n 's/^version = "\(.*\)"$/\1/p' | head -n 1; }
# True when $1 is a greater version than $2.
greater() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }

changed=$(git diff --name-only "$BASE" "$HEAD" | while IFS= read -r path; do
  case $path in
    .github/*|scripts/*|README.md|LICENSE|.gitignore|catalog.json) ;;
    *) printf '%s\n' "$path" ;;
  esac
done)
if [ -z "$changed" ]; then
  echo "the provider did not change: no version to raise"
  exit 0
fi

new=$(version_at "$HEAD")
old=$(version_at "$BASE")
[ -n "$new" ] || { echo "cannot read the version of pyproject.toml" >&2; exit 1; }
if [ -n "$old" ] && ! greater "$new" "$old"; then
  message="the provider changed but its version is still $new (it is $old on the base): raise \"version\" in pyproject.toml, its image is published under that version"
  if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::error file=pyproject.toml::$message"; else echo "$message" >&2; fi
  echo "changed:" >&2
  printf '%s\n' "$changed" | sed 's/^/  /' >&2
  exit 1
fi
echo "version ${old:-?} -> $new"
