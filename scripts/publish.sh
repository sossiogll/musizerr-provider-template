#!/bin/sh
# Publish the provider's image for linux/amd64 and linux/arm64 and pin it in catalog.json.
#
#   scripts/publish.sh
#
#   IMAGE_NAMESPACE  where the image goes (default: ghcr.io/<owner of the origin remote>, lower case)
#   CATALOG_NAME     the catalog's name, when catalog.json does not exist yet (default: "<repository> providers")
#   BUILDER          the buildx builder (default musizerr-publish, docker-container driver, created when missing:
#                    the default driver cannot push an image for several platforms)
#
# Steps: (1) build the image for this machine and ask the provider for its org.musizerr.provider.* labels (the
# provider describes itself: name, roles, contract version, permissions), (2) build it with them for both
# platforms and push <namespace>/musizerr-provider-<name>:<version of pyproject.toml>, (3) write the entry in
# catalog.json, pinned by the digest of the multi-architecture index. Commit catalog.json afterwards: it is what
# a Musizerr source points at. Needs Docker and `docker login ghcr.io` (a token that may write packages); the
# GitHub workflow .github/workflows/publish.yml runs this same script.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [ -z "${IMAGE_NAMESPACE:-}" ]; then
  OWNER=$(git remote get-url origin 2>/dev/null | sed -n 's#.*github\.com[:/]\([^/]*\)/.*#\1#p' | tr '[:upper:]' '[:lower:]')
  [ -n "$OWNER" ] || { echo "set IMAGE_NAMESPACE (no GitHub origin remote to take the owner from)" >&2; exit 2; }
  IMAGE_NAMESPACE=ghcr.io/$OWNER
fi
CATALOG_NAME=${CATALOG_NAME:-"$(basename "$ROOT") providers"}
BUILDER=${BUILDER:-musizerr-publish}
PLATFORMS=linux/amd64,linux/arm64
VERSION=$(sed -n 's/^version = "\(.*\)"$/\1/p' pyproject.toml | head -1)
BASE=$(sed -n 's/^FROM \([^ ]*\).*/\1/p' Dockerfile | head -1)
[ -n "$VERSION" ] && [ -n "$BASE" ] || { echo "cannot read the version (pyproject.toml) or the base image (Dockerfile)" >&2; exit 1; }

TMP=$(mktemp -d)
LOCAL=musizerr-provider-publish-$(basename "$ROOT"):build
trap 'rm -rf "$TMP"; docker image rm -f "$LOCAL" >/dev/null 2>&1 || true' EXIT

echo "== labels" >&2
docker pull -q "$BASE" >/dev/null
docker build -q --provenance=false -t "$LOCAL" . >/dev/null
docker run --rm "$LOCAL" --print-labels >"$TMP/labels"
NAME=$(sed -n 's/^org.musizerr.provider.name=//p' "$TMP/labels")
[ -n "$NAME" ] || { echo "the provider printed no name label" >&2; exit 1; }
IMAGE=$IMAGE_NAMESPACE/musizerr-provider-$NAME
sed 's/^/   /' "$TMP/labels" >&2

set --
while IFS= read -r line; do
  set -- "$@" --label "$line"
done <"$TMP/labels"
for key in org.opencontainers.image.description org.opencontainers.image.url; do
  value=$(docker inspect -f "{{index .Config.Labels \"$key\"}}" "$LOCAL")
  [ -z "$value" ] || printf '%s=%s\n' "$key" "$value" >>"$TMP/labels"
done
# GHCR reads the repository, the description and the license of a multi-platform image from the annotations of
# its index, not from the labels of each platform's image: without them the package is linked to no repository.
for key in org.opencontainers.image.source org.opencontainers.image.description org.opencontainers.image.licenses; do
  value=$(docker inspect -f "{{index .Config.Labels \"$key\"}}" "$LOCAL")
  [ -z "$value" ] || set -- "$@" --annotation "index:$key=$value"
done

docker buildx inspect "$BUILDER" >/dev/null 2>&1 || docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
echo "== $IMAGE:$VERSION ($PLATFORMS)" >&2
docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" --provenance=false --sbom=false \
  "$@" -t "$IMAGE:$VERSION" --metadata-file "$TMP/meta.json" --push . >&2
DIGEST=$(sed -n 's/.*"containerimage.digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$TMP/meta.json" | head -1)
[ -n "$DIGEST" ] || { echo "could not read the digest of the pushed index" >&2; exit 1; }

cp scripts/catalog_entry.py "$TMP/"
[ ! -f catalog.json ] || cp catalog.json "$TMP/catalog.json"
docker run --rm --user "$(id -u):$(id -g)" -v "$TMP":/work --entrypoint python "$BASE" /work/catalog_entry.py \
  --catalog /work/catalog.json --image "$IMAGE" --digest "$DIGEST" --labels /work/labels --catalog-name "$CATALOG_NAME" >&2
cp "$TMP/catalog.json" catalog.json
echo "$DIGEST"
