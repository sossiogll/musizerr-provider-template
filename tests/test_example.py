"""
The tests of the example provider. They need no network and no Musizerr: the provider is built
with a StaticProviderContext (its settings and timeouts, as the host would give them) and its
HTTP is replaced by recorded answers.
"""
from __future__ import annotations

import io
import json
import urllib.error
import urllib.parse

import pytest

from musizerr_sdk.auth import AuthSession
from musizerr_sdk.conformance import check_provider
from musizerr_sdk.context import StaticProviderContext
from musizerr_sdk.failures import classify_exception
from musizerr_sdk.manifest import build

import musizerr_provider_example as example
from musizerr_provider_example import ExampleMetadataProvider

SONG = {
    "wrapperType": "track", "trackId": 1440857781, "artistId": 3296287, "collectionId": 1440857775,
    "trackName": "Karma Police", "artistName": "Radiohead", "collectionName": "OK Computer",
    "trackTimeMillis": 264066, "releaseDate": "1997-05-21T07:00:00Z", "trackNumber": 6, "discNumber": 1,
    "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg",
    "previewUrl": "https://audio-ssl.itunes.apple.com/preview.m4a",
}


@pytest.fixture
def requests(monkeypatch):
    """Answer every request with ``answers`` (a list, consumed in order) and remember the URLs asked."""
    seen: list[str] = []
    answers: list[object] = []

    def urlopen(request, timeout):
        seen.append(request.full_url)
        answer = answers.pop(0)
        if isinstance(answer, BaseException):
            raise answer
        return io.BytesIO(json.dumps(answer).encode())

    monkeypatch.setattr(example.urllib.request, "urlopen", urlopen)
    return seen, answers


def provider(**settings) -> ExampleMetadataProvider:
    return ExampleMetadataProvider(StaticProviderContext(settings=settings))


def test_the_provider_follows_the_generic_rules_of_the_contract():
    check_provider(provider())


def test_it_declares_what_the_sandbox_and_the_host_read():
    manifest = build(provider())
    assert manifest.name == "example"
    assert manifest.roles == ("metadata",)
    assert manifest.permissions.egress == ("itunes.apple.com:443",)
    assert {"search_tracks", "get_track"} <= set(manifest.implements)


def test_a_search_returns_the_songs_as_tracks(requests):
    seen, answers = requests
    answers.append({"results": [SONG, {"wrapperType": "collection", "collectionId": 1}]})

    tracks = provider(country="IT").search_tracks("karma police", AuthSession.anonymous(), limit=5)

    assert len(tracks) == 1
    track = tracks[0]
    assert (track.title, track.artist, track.album, track.duration_ms) == ("Karma Police", "Radiohead", "OK Computer", 264066)
    assert (track.provider, track.provider_id, track.year, track.track_number) == ("example", "1440857781", 1997, 6)
    assert track.cover_url.endswith("600x600bb.jpg")
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(seen[0]).query)
    assert query["term"] == ["karma police"] and query["limit"] == ["5"] and query["country"] == ["IT"]


def test_a_track_it_does_not_have_is_none(requests):
    _seen, answers = requests
    answers.append({"resultCount": 0, "results": []})
    assert provider().get_track("1", AuthSession.anonymous()) is None


def test_a_failure_of_the_service_is_raised_and_classified_by_its_status(requests):
    _seen, answers = requests
    answers.append(urllib.error.HTTPError(example.API, 503, "Service Unavailable", {}, None))

    with pytest.raises(urllib.error.HTTPError) as raised:
        provider().search_tracks("x", AuthSession.anonymous())

    # What the runner does with it on the provider's side, before the host sees it.
    assert classify_exception(raised.value).kind == "upstream_error"


def test_the_country_setting_is_validated():
    assert provider().validate_config({"country": "IT"})
    assert not provider().validate_config({"country": "Italy"})
