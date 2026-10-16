"""An example Musizerr provider: track search and lookup through the iTunes Search API.

It is the starting point of a provider of your own (see README.md): a metadata provider
that needs no account and no dependency but the SDK, the standard library doing the HTTP.
Replace the service, keep the shape:

- it imports ``musizerr_sdk`` and nothing else of Musizerr;
- it declares what it is (``name``, ``label``, ``auth``, ``permissions``) as data;
- it talks only to the destinations its ``permissions`` declare (the sandbox grants
  nothing else, and reaches them through a proxy the standard library and httpx pick
  up from the environment by themselves);
- it raises on a failure of its service and returns data: the host classifies the
  failure (an ``urllib.error.HTTPError`` or an ``httpx.HTTPStatusError`` carries its
  status) and decides what to do.
"""
from __future__ import annotations

import json
import urllib.parse
import urllib.request

from musizerr_sdk.auth import AccountModel, AuthDefinition, AuthFlow, AuthSession
from musizerr_sdk.interfaces import PROVIDER_API_VERSION, MetadataProvider
from musizerr_sdk.models import Track
from musizerr_sdk.permissions import Permissions
from musizerr_sdk.settings import ProviderSetting
from musizerr_sdk.text import parse_year

API = "https://itunes.apple.com"


class ExampleMetadataProvider(MetadataProvider):
    name = "example"
    label = "Example"
    provider_api_version = PROVIDER_API_VERSION
    # The only destination the sandbox lets it reach.
    permissions = Permissions(egress=("itunes.apple.com:443",))
    # A public service: no account, whoever the viewer.
    auth = AuthDefinition(flow=AuthFlow.NONE, account_model=AccountModel.NONE)

    def config_schema(self) -> list[ProviderSetting]:
        # What the admin can set, placed under the provider in Musizerr's settings.
        return [
            ProviderSetting(
                key="country", type="string", default="US", label="Store country",
                description="The two-letter country of the store to search.", required=False,
            ),
        ]

    def validate_config(self, config: dict) -> bool:
        country = config.get("country", "US")
        return isinstance(country, str) and len(country) == 2 and country.isalpha()

    def test_connection(self, session: AuthSession) -> str | None:
        try:
            self._get("/search", {"term": "test", "entity": "song", "limit": 1})
        except OSError as exc:  # urllib's errors are OSErrors
            return str(exc)
        return None

    # ---- the metadata contract ------------------------------------------

    def search_tracks(self, query: str, session: AuthSession, limit: int = 20) -> list[Track]:
        data = self._get("/search", {"term": query, "entity": "song", "limit": min(limit, 200)})
        return [self._track(item) for item in data.get("results", []) if item.get("wrapperType") == "track"]

    def get_track(self, provider_id: str, session: AuthSession) -> Track | None:
        data = self._get("/lookup", {"id": provider_id, "entity": "song"})
        tracks = [item for item in data.get("results", []) if item.get("wrapperType") == "track"]
        return self._track(tracks[0]) if tracks else None

    # ---- the service ----------------------------------------------------

    def _get(self, path: str, params: dict) -> dict:
        params = {**params, "country": self.context.setting("country", "US") or "US"}
        url = f"{API}{path}?{urllib.parse.urlencode(params)}"
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=self.context.http_timeout) as response:
            return json.load(response)

    def _track(self, item: dict) -> Track:
        artwork = item.get("artworkUrl100") or None
        return Track(
            title=item.get("trackName", ""),
            artist=item.get("artistName", ""),
            album=item.get("collectionName", ""),
            duration_ms=int(item.get("trackTimeMillis") or 0),
            cover_url=artwork.replace("100x100", "600x600") if artwork else None,
            preview_url=item.get("previewUrl") or None,
            provider=self.name,
            provider_id=str(item["trackId"]),
            artist_provider_id=str(item.get("artistId", "")),
            album_provider_id=str(item.get("collectionId", "")),
            year=parse_year(item.get("releaseDate")),
            track_number=item.get("trackNumber"),
            disc_number=item.get("discNumber"),
        )
