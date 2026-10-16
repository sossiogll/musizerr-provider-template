# The image of the provider. The base image holds Python and the musizerr-sdk; the major version in its tag is
# the provider API version (the contract) this provider implements.
FROM ghcr.io/sossiogll/musizerr-provider-base:5

# The catalog entry is written from these labels (scripts/publish.sh). Set the source to YOUR repository: it
# links the package GHCR creates to it.
LABEL org.opencontainers.image.description="An example Musizerr provider: track search through the iTunes Search API." \
      org.opencontainers.image.url="https://performance-partners.apple.com/search-api" \
      org.opencontainers.image.source="https://github.com/sossiogll/musizerr-provider-template" \
      org.opencontainers.image.licenses="MIT-0"

COPY . /tmp/provider
RUN pip install /tmp/provider && rm -rf /tmp/provider

# The gateway appends --socket and --egress-socket. `--print-labels` prints the org.musizerr.provider.* labels
# (name, roles, contract version, permissions) the provider declares: scripts/publish.sh puts them on the image.
ENTRYPOINT ["python", "-m", "musizerr_sdk.runner", "--provider", "musizerr_provider_example:ExampleMetadataProvider"]
