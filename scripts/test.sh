#!/bin/sh
# Run the tests in a throwaway container of the base image, which already holds Python and the SDK: nothing runs
# on your machine but Docker, and you need no checkout of Musizerr.
#
#   scripts/test.sh [pytest arguments]
#
#   BASE_IMAGE  the image to test in (default: the FROM of the Dockerfile)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=${BASE_IMAGE:-$(sed -n 's/^FROM \([^ ]*\).*/\1/p' "$ROOT/Dockerfile" | head -1)}
# The container never writes to the mount: the provider is copied to its own filesystem.
exec docker run --rm -e PIP_DISABLE_PIP_VERSION_CHECK=1 -e PIP_ROOT_USER_ACTION=ignore -e PYTHONDONTWRITEBYTECODE=1 \
  -v "$ROOT":/mnt/provider:ro --entrypoint sh "$BASE" -ec '
    cp -r /mnt/provider /tmp/provider && cd /tmp/provider
    pip install -q ".[test]"
    python -m pytest -p no:cacheprovider "$@"
  ' sh "$@"
