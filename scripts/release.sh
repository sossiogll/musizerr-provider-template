#!/bin/sh
# Tag and release the provider when its version has no tag yet: what a push to master does
# (.github/workflows/release.yml).
#
#   scripts/release.sh [--dry-run]
#
#   --dry-run        print the release it would create, and create none
#
#   IMAGE_NAMESPACE  the images it releases (default: ghcr.io/<owner of the origin remote>, lower case); an entry of
#                    catalog.json elsewhere is left out (the template's own example, in a repository made from it)
#   RELEASE_COMMIT   the commit the tag is made on (default GITHUB_SHA, else HEAD)
#
# The version is the one in pyproject.toml, for the entry of catalog.json (the provider of this repository). When origin
# has no tag <name>-v<version>, it checks that <image>:<version> is the image catalog.json pins (the same digest of the
# multi-architecture index) and creates the GitHub release "<label> <version>" with its tag on the commit; the notes give
# the image pinned by its digest and the permissions it declares. A tag that exists is left alone: a version is released
# once. When the image of the version is missing or is not the one pinned, nothing is released and the exit status is
# non-zero. Nothing is committed. Needs git, jq, Docker with buildx (logged in to the registry for private packages)
# and gh (GH_TOKEN).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DRY_RUN=false
case ${1:-} in
  --dry-run) DRY_RUN=true ;;
  "") ;;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
cd "$ROOT"
if [ -z "${IMAGE_NAMESPACE:-}" ]; then
  OWNER=$(git remote get-url origin 2>/dev/null | sed -n 's#.*github\.com[:/]\([^/]*\)/.*#\1#p' | tr '[:upper:]' '[:lower:]')
  [ -n "$OWNER" ] || { echo "set IMAGE_NAMESPACE (no GitHub origin remote to take the owner from)" >&2; exit 2; }
  IMAGE_NAMESPACE=ghcr.io/$OWNER
fi
NAMESPACE=$IMAGE_NAMESPACE
VERSION=$(sed -n 's/^version = "\(.*\)"$/\1/p' pyproject.toml | head -n 1)
[ -n "$VERSION" ] || { echo "cannot read the version from pyproject.toml" >&2; exit 1; }
COMMIT=$(git rev-parse "${RELEASE_COMMIT:-${GITHUB_SHA:-HEAD}}^{commit}")
[ -f catalog.json ] || { echo "no catalog.json: nothing to release"; exit 0; }

warn() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::warning::$*"; else echo "warning: $*" >&2; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The release notes of the entry in $TMP/entry.json, at version $1.
notes() {
  jq -r --arg version "$1" '
    def setting: "the setting `\(.)`";
    def ports: if .ports == "any" then "any port"
      elif (.ports | tostring | test("-")) then "ports \(.ports)" else "port \(.ports)" end;
    def limit: {memory_mb: "memory (MB)", open_files: "open files", processes: "processes"}[.key] // .key;
    .permissions as $p
    | [ (($p.egress // [])[]
          | if startswith("*.") then "- connects to `\(.)`: any subdomain of \(ltrimstr("*.") | sub(":[0-9]+$"; ""))"
            else "- connects to `\(.)`" end),
        (($p.egress_from_settings // [])[] | "- connects to the server named by \(setting)"),
        (($p.tcp_from_settings // [])[] | "- opens raw TCP connections to the host named by \(.setting | setting), on \(ports)"),
        (($p.filesystem_from_settings // [])[]
          | "- \(if .mode == "rw" then "reads and writes" else "reads" end) the folder named by \(.setting | setting)"),
        (($p.limits // {}) | to_entries[] | select(.value != null) | "- limit: \(limit) \(.value)")
      ] as $lines
    | "## Image",
      "",
      "```",
      "\(.image)@\(.digest)",
      "```",
      "",
      "`\(.image):\($version)`, pinned in `catalog.json` by the digest of its multi-architecture index (linux/amd64, linux/arm64). Roles: \(.roles | join(", ")). Provider API version \(.provider_api_version).",
      "",
      "## Permissions",
      "",
      (if ($lines | length) == 0 then "None: no network, no folder, no limit of its own." else $lines[] end),
      "",
      "<details><summary>As the image declares them (<code>org.musizerr.provider.permissions</code>)</summary>",
      "",
      "```json"
  ' "$TMP/entry.json"
  jq '.permissions' "$TMP/entry.json"
  printf '%s\n' '```' '' '</details>'
}

jq -r '.providers[].name' catalog.json >"$TMP/names"
released=0
failed=0
while IFS= read -r name; do
  jq --arg name "$name" '[.providers[] | select(.name == $name)][0]' catalog.json >"$TMP/entry.json"
  image=$(jq -r .image "$TMP/entry.json")
  digest=$(jq -r .digest "$TMP/entry.json")
  label=$(jq -r '.label // .name' "$TMP/entry.json")
  case $image in
    "$NAMESPACE"/*) ;;
    *) echo "$name: $image is not under $NAMESPACE, left out"; continue ;;
  esac
  version=$VERSION
  tag=$name-v$version

  status=0
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null || status=$?
  case $status in
    0) echo "$name $version: $tag exists"; continue ;;
    2) ;;
    *) echo "cannot list the tags of origin" >&2; exit 1 ;;
  esac

  if ! published=$(docker buildx imagetools inspect "$image:$version" --format '{{.Manifest.Digest}}' 2>"$TMP/error"); then
    warn "$name $version: $image:$version cannot be read ($(head -n 1 "$TMP/error")): not released"
    failed=1
    continue
  fi
  if [ "$published" != "$digest" ]; then
    warn "$name $version: catalog.json pins $digest but $image:$version is $published: not released"
    failed=1
    continue
  fi

  notes "$version" >"$TMP/notes.md"
  if $DRY_RUN; then
    echo "$name $version: would create $tag on $COMMIT, release \"$label $version\""
    sed 's/^/    /' "$TMP/notes.md"
  else
    gh release create "$tag" --target "$COMMIT" --title "$label $version" --notes-file "$TMP/notes.md" >/dev/null
    echo "$name $version: released $tag on $COMMIT"
  fi
  released=$((released + 1))
done <"$TMP/names"

[ "$released" -gt 0 ] || echo "nothing to release"
exit $failed
