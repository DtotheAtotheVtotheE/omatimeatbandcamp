#!/usr/bin/env python3
"""Generate tests/qml/fixtures/library.json: a small SYNTHETIC library in the exact shape
backend/library.py writes, with the albums the Phase 4 QML tests need (pre-orders, a fully
released contrast, a wrap fixture, sort/edge cases). No real account data.

    python3 tests/qml/make_fixture.py
"""
import json
import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from backend.model import (Album, Playlist, Track, R_SUBSONIC, R_UNRELEASED)  # noqa: E402

LONG_TITLE = ("A Very Long Album Title That Certainly Needs To Wrap Onto A Second Line And Then Keep Going With "
              "Many More Words So That It Must Be Cut With An Ellipsis After The Second Line Because Nobody Reads This Far")


def sub_tracks(prefix, album, artist, n, year=None, durations=None):
    return [Track(title=f"{album} track {i}" if not prefix else prefix[i - 1], artist=artist, album=album, track_number=i,
                  duration=(durations[i - 1] if durations else 180.0 + i), year=year, streamable=True,
                  streamable_reason=R_SUBSONIC, subsonic_id=f"t:fx-{zlib.crc32(album.encode()) % 10**6}-{i}") for i in range(1, n + 1)]


def unreleased(titles, album, artist):
    return [Track(title=t, artist=artist, album=album, track_number=i, duration=0.0, streamable=False,
                  streamable_reason=R_UNRELEASED, bandcamp_id=str(9000 + i)) for i, t in enumerate(titles, 1)]


albums = []


def add(a, tracks, source, declared=None, loaded=True):
    a.declared_track_count = len(tracks) if declared is None else declared
    if loaded:
        a.set_tracks(tracks, source)
    albums.append(a)
    return a


# --- the named fixtures ------------------------------------------------------------------
fi = Album(title="First Impressions (Deluxe Edition)", artist="Shamek Farrah", bandcamp_id="2025444064",
           bandcamp_url="https://shamekfarrah.bandcamp.com/album/first-impressions-deluxe-edition",
           purchased="20 Oct 2026 21:36:25 GMT", is_preorder=True, album_is_preorder=True,
           release_date="27 Nov 2026 00:00:00 GMT", sources=["bandcamp"])
add(fi, unreleased(["Meterologicly Tuned", "Watch What Happens Now", "Umoja Suite", "First Impressions", "Bantu Blues",
                    "Two For Three", "Aisha"], fi.title, fi.artist), "bandcamp-page")

dee = Album(title="La Dee La La", artist="Shamek Farrah & Folks", subsonic_id="a:fx-dee", bandcamp_id="4039254352",
            purchased="21 Oct 2026 02:28:23 GMT", sources=["bandcamp", "subsonic"])
add(dee, sub_tracks(["La Dee La La Song", "Waiting For Marvin", "The White Lady", "Along Came Ron Rahsaan"], dee.title, dee.artist, 4,
                    year=2021, durations=[558, 454, 593, 598]), "subsonic")

croc = Album(title="Crocbrain, or, Two Big Steps For Mankind", artist="Ismatic Guru", subsonic_id="a:fx-croc",
             purchased="05 Mar 2024 12:00:00 GMT", sources=["bandcamp", "subsonic"])
add(croc, sub_tracks(None, croc.title, croc.artist, 6, year=2008), "subsonic")

# --- a second pre-order with ONE released track (partial availability) -------------------
fut = Album(title="Future Sounds", artist="Aaa Artist", bandcamp_id="9100", bandcamp_url="https://example.invalid/album/future-sounds",
            purchased="22 Oct 2026 10:00:00 GMT", is_preorder=True, album_is_preorder=True,
            release_date="15 Jan 2027 00:00:00 GMT", sources=["bandcamp"])
add(fut, [Track(title="Released Single", artist=fut.artist, album=fut.title, track_number=1, duration=201.0, streamable=True,
                streamable_reason="page-file", bandcamp_id="9101")]
    + unreleased(["Coming Soon", "Later Still"], fut.title, fut.artist)[0:0]
    + [Track(title=t, artist=fut.artist, album=fut.title, track_number=i, duration=0.0, streamable=False,
             streamable_reason=R_UNRELEASED, bandcamp_id=str(9100 + i)) for i, t in ((2, "Coming Soon"), (3, "Later Still"))],
    "bandcamp-page")

# --- sort / edge cases --------------------------------------------------------------------
add(Album(title="Zebra Crossing", artist="Mmm Band", subsonic_id="a:fx-zebra", purchased="01 Jan 2020 00:00:00 GMT", sources=["subsonic"]),
    sub_tracks(None, "Zebra Crossing", "Mmm Band", 3, year=1999), "subsonic")
add(Album(title="alpha", artist="The Aardvarks", subsonic_id="a:fx-alpha", purchased="05 May 2024 08:00:00 GMT", sources=["subsonic"]),
    sub_tracks(None, "alpha", "The Aardvarks", 3, year=2015), "subsonic")
add(Album(title="Émile's Song", artist="émile", subsonic_id="a:fx-emile", purchased="03 Mar 2019 08:00:00 GMT", sources=["subsonic"]),
    sub_tracks(None, "Émile's Song", "émile", 2, year=2001), "subsonic")
add(Album(title="Same Year Early", artist="Bbb", subsonic_id="a:fx-same", purchased="06 Jun 2023 08:00:00 GMT", sources=["subsonic"]),
    sub_tracks(None, "Same Year Early", "Bbb", 2, year=2015), "subsonic")
add(Album(title="No Date Album", artist="Zed", subsonic_id="a:fx-nodate", sources=["subsonic"]),
    sub_tracks(None, "No Date Album", "Zed", 2), "subsonic")
add(Album(title="Truncated Compilation", artist="Various", subsonic_id="a:fx-trunc", sources=["subsonic"]),
    sub_tracks(None, "Truncated Compilation", "Various", 3), "subsonic", declared=50)
add(Album(title="Empty Album", artist="Nobody", subsonic_id="a:fx-empty", sources=["subsonic"]), [], "subsonic", declared=0)
LONG_TRACK = ("An Extremely Long Track Title That Has To Wrap Across Several Lines Of The Track List Instead Of Being Cut Off "
              "In The Middle Of A Word By A Single Line Truncation")
add(Album(title=LONG_TITLE, artist="Long Title Artist", subsonic_id="a:fx-long", sources=["subsonic"]),
    sub_tracks([LONG_TRACK, "Short"], "Long", "Long Title Artist", 2), "subsonic")
add(Album(title="Unloaded Album", artist="Pending", subsonic_id="a:fx-unloaded", sources=["subsonic"]), [], "subsonic", declared=9, loaded=False)

# --- playlists -----------------------------------------------------------------------------
pp = Playlist(id="pl:fx-1", name="Postpunky?", declared_track_count=5, tracks_loaded=True)
pp.tracks = sub_tracks(["Devolution", "Second", "Third", "Fourth", "Fifth"], "Mixed", "Various", 5)
mini = Playlist(id="pl:fx-2", name="Rock & Roll Faves", declared_track_count=1, tracks_loaded=True)
mini.tracks = sub_tracks(["Only Song"], "Mixed", "Various", 1)

out = {"schema": 1, "meta": {"user": "fixture-user", "finished": 1792800000, "phase": "complete"},
       "match_report": {}, "albums": [a.to_dict() for a in albums], "playlists": [pp.to_dict(), mini.to_dict()]}
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "library.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=1, ensure_ascii=False)
    f.write("\n")

def key(s):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if not unicodedata.combining(c))

def titles(items):
    return [a.title[:16] for a in items]

by = lambda a: (key(a.title), key(a.artist), a.subsonic_id or a.bandcamp_id)
print("added  :", titles(sorted(albums, key=lambda a: (-(a.purchased_ts or 0),) + by(a))))
print("artist :", titles(sorted(albums, key=lambda a: (key(a.artist),) + by(a))))
print("title  :", titles(sorted(albums, key=by)))
def rk(a):
    return a.release_ts or (__import__("calendar").timegm((a.year, 1, 1, 0, 0, 0)) if a.year else 0)
print("release:", titles(sorted(albums, key=lambda a: (0 if rk(a) else 1, -rk(a), key(a.artist)) + by(a))))
print(f"wrote {path} ({len(albums)} albums, 2 playlists)")
