# A Musizerr provider

The starting point of a provider for [Musizerr](https://github.com/sossiogll/musizerr): a package of its own, with its
tests and its image, offered to Musizerr instances through a catalog. The example in it is a metadata provider that
searches the iTunes Search API; replace it with yours.

A provider imports `musizerr_sdk` (the provider contract, in the base image) and nothing else of Musizerr. Musizerr runs it
in a sandbox: no network but the destinations it declares, no environment, no file but its own workspace. It never sees
Musizerr's database, settings store or other providers; it gets its own settings, its timeouts and the user's session with
each call, and returns data. The guide is `docs/provider-authors.md` of the Musizerr repository; the contract is
`musizerr_sdk/interfaces.py`.

## Start

1. **Use this template** (GitHub) to create your repository.
2. Rename the package: `musizerr_provider_example/` and its name in `pyproject.toml` (`[project] name`, the
   `packages.find` include) and in the `ENTRYPOINT` of the `Dockerfile`; set `org.opencontainers.image.source` in the
   `Dockerfile` to your repository.
3. Write your provider in it: pick its roles (the classes it extends: `MetadataProvider`, `DownloadProvider`,
   `LyricsProvider`, `StorageProvider`, `SyncProvider`, `IdentificationProvider`), give it a unique `name`, declare its
   `auth` and its `permissions` (every host it talks to, `host:443`), and override the methods it supports. Put its
   dependencies in `pyproject.toml`.
4. Keep the tests: `check_provider` (`musizerr_sdk.conformance`) checks the rules every provider follows, and your own
   tests check what it does with recorded answers of its service (no network in the tests).

## Test

```sh
scripts/test.sh
```

The tests run in a throwaway container of the base image (Python and the SDK): you need Docker and nothing else, no
checkout of Musizerr. The `test` workflow runs them on every push and pull request.

## Publish

Raise `version` in `pyproject.toml`, then run the `publish` workflow (Actions > publish > Run workflow), or from your
machine, logged in to GHCR with a token that may write packages:

```sh
docker login ghcr.io
scripts/publish.sh
```

It builds the image for `linux/amd64` and `linux/arm64`, asks the provider for its `org.musizerr.provider.*` labels (its
name, roles, contract version and permissions: Musizerr's gateway checks the image against them), pushes
`ghcr.io/<owner>/musizerr-provider-<name>:<version>` and writes the entry in `catalog.json`, pinned by the digest of the
image. The workflow commits `catalog.json`; from your machine, commit it yourself.

GHCR creates a new package as **private**. Make it public in the package's settings to let anyone install it, or keep
it private and give each person access (their own token, below).

## Install it in Musizerr

In Musizerr, Administration > Providers > Sources, add the URL of your catalog:

```
https://raw.githubusercontent.com/<owner>/<repository>/<branch>/catalog.json
```

For a private repository or private packages, add the source with a token that can read them (a classic GitHub token
with `repo` and `read:packages`). Musizerr shows the permissions of the provider before you install it, and the
difference when an update asks for more.

## License

The template is released under the MIT No Attribution license (`LICENSE`): your provider is yours, under the license
you choose. The SDK it builds on (`musizerr-sdk`, in the base image) is under the GNU LGPL, version 3 or later.
