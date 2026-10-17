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

## Branches, versions and publishing

The repository has two branches: `dev`, where changes land, and `master`, what Musizerr instances read. A repository
made from this template gets `master` only: create `dev` from it (`git push origin master:dev`), and in the repository's
settings protect `master`, with the checks `test`, `master takes dev only` and `provider version` required. Then:

1. **Work on a branch from `dev` and open a pull request into `dev`.** If the provider changed (any file outside
   `.github/`, `scripts/`, `README.md`, `LICENSE`, `.gitignore` and `catalog.json`), raise `version` in `pyproject.toml`
   in the same pull request: the check `provider version` (`scripts/version-check.sh`) fails otherwise. The version is
   the tag of the image, and a version is published once.
2. **The merge publishes, on `dev`.** Every push to `dev` runs the `publish` workflow: when
   `ghcr.io/<owner>/musizerr-provider-<name>:<version>` does not exist yet, it runs the tests, builds the image for
   `linux/amd64` and `linux/arm64` (`scripts/publish.sh`), pushes it, writes its entry in `catalog.json`, pinned by the
   digest of the image, and commits `catalog.json` to `dev`. A push that does not raise the version publishes nothing.
3. **Open a pull request from `dev` into `master`.** It brings the new `catalog.json` to `master` (the check
   `master takes dev only` refuses one from any other branch).
4. **The merge releases, on `master`.** The `release` workflow (`scripts/release.sh`) tags the merge commit
   `<name>-v<version>` and creates the GitHub release "<label> <version>", with the image pinned by its digest and the
   permissions the provider declares.

`scripts/publish.sh` also runs from your machine, logged in to GHCR with a token that may write packages
(`docker login ghcr.io`); it never pushes a version that is published already (`scripts/publish.sh --check` says whether
it is). Commit `catalog.json` yourself then, on a branch into `dev`.

The image describes itself: the build asks the provider for its `org.musizerr.provider.*` labels (its name, roles,
contract version and permissions), and Musizerr's gateway checks the image against them.

GHCR creates a new package as **private**. Make it public in the package's settings to let anyone install it, or keep
it private and give each person access (their own token, below). The workflows push with the repository's
`GITHUB_TOKEN`: a package the workflow created is connected to the repository; one you pushed from your machine first
needs it, in the package's settings → *Manage Actions access* → *Add repository* (this repository, role *Write*).

## Install it in Musizerr

In Musizerr, Administration > Providers > Sources, add the URL of your catalog, the one on `master`:

```
https://raw.githubusercontent.com/<owner>/<repository>/master/catalog.json
```

It does not change from one version to the next: each release on `master` updates the file behind it, and Musizerr
offers the new digest as an update. For a private repository or private packages, add the source with a token that can
read them (a classic GitHub token with `repo` and `read:packages`). Musizerr shows the permissions of the provider before
you install it, and the difference when an update asks for more.

## License

The template is released under the MIT No Attribution license (`LICENSE`): your provider is yours, under the license
you choose. The SDK it builds on (`musizerr-sdk`, in the base image) is under the GNU LGPL, version 3 or later.
