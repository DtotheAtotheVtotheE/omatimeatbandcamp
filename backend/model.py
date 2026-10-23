"""Library data model.

Rules this module exists to enforce:

* Display text is always entity-decoded (`textnorm.clean`) on the way in.
* Every Track carries an explicit `streamable` bool and the reason for it.
* An Album's `tracks` holds only tracks a source actually returned. Nothing is
  ever invented to fill a gap: no first-track / featured-track substitution, no
  placeholder rows for a declared-but-missing track, no padding of empty albums.
  The gap is reported through `declared_track_count` / `missing_track_count` /
  `completeness` instead.
* Pre-order state (`is_preorder`, `album_is_preorder`, `release_date`) is stored
  as received from the page's data-tralbum.
"""
from dataclasses import dataclass, field, asdict
from typing import Optional

from .textnorm import album_key, clean

# streamable_reason values
R_SUBSONIC = "subsonic-listed"        # the Subsonic server returned the track (stream endpoint serves it)
R_PAGE_FILE = "page-file"             # data-tralbum trackinfo carries a stream file
R_UNRELEASED = "unreleased"           # data-tralbum marks the track unreleased (pre-order)
R_DISABLED = "streaming-disabled"     # source says streaming is switched off
R_NO_FILE = "no-stream-file"          # source offered no stream file for the track

# Album.completeness values
C_UNLOADED = "unloaded"      # tracklist not fetched yet; nothing is claimed about tracks
C_EMPTY = "empty"            # source returned zero tracks
C_PARTIAL = "partial"        # source returned fewer tracks than it declares
C_COMPLETE = "complete"      # returned == declared (or nothing was declared)


@dataclass
class Track:
    title: str
    artist: str = ""
    album: str = ""
    track_number: Optional[int] = None
    duration: Optional[float] = None
    streamable: bool = False
    streamable_reason: str = R_NO_FILE
    subsonic_id: Optional[str] = None
    bandcamp_id: Optional[str] = None
    subsonic_album_id: Optional[str] = None

    def __post_init__(self):
        self.title = clean(self.title)
        self.artist = clean(self.artist)
        self.album = clean(self.album)
        self.streamable = bool(self.streamable)

    def to_dict(self):
        return asdict(self)

    @classmethod
    def from_dict(cls, d):
        return cls(**{k: d.get(k) for k in cls.__dataclass_fields__ if k in d})


@dataclass
class Album:
    title: str
    artist: str
    kind: str = "album"                      # "album" | "single" (a purchased single track)
    subsonic_id: Optional[str] = None
    cover_art_id: Optional[str] = None
    bandcamp_id: Optional[str] = None
    bandcamp_url: str = ""
    web_item_ids: list = field(default_factory=list)  # every web-feed item folded into this album (single-track purchases)
    purchased: Optional[str] = None
    declared_track_count: Optional[int] = None
    tracks: list = field(default_factory=list)
    tracks_loaded: bool = False
    is_preorder: bool = False
    album_is_preorder: Optional[bool] = None
    release_date: Optional[str] = None
    tracks_source: Optional[str] = None      # "subsonic" | "bandcamp-page"
    sources: list = field(default_factory=list)  # which of "subsonic" / "bandcamp" know this album

    def __post_init__(self):
        self.title = clean(self.title)
        self.artist = clean(self.artist)

    @property
    def key(self):
        return album_key(self.artist, self.title)

    @property
    def returned_track_count(self):
        return len(self.tracks)

    @property
    def streamable_track_count(self):
        return sum(1 for t in self.tracks if t.streamable)

    @property
    def missing_track_count(self):
        if self.declared_track_count is None or not self.tracks_loaded:
            return 0
        return max(0, self.declared_track_count - len(self.tracks))

    @property
    def completeness(self):
        if not self.tracks_loaded:
            return C_UNLOADED
        if not self.tracks:
            return C_EMPTY
        if self.missing_track_count:
            return C_PARTIAL
        return C_COMPLETE

    def set_tracks(self, tracks, source):
        """Store exactly the tracks the source returned; sorted for display, never extended."""
        self.tracks = sorted(tracks, key=lambda t: (t.track_number is None, t.track_number or 0))
        self.tracks_loaded = True
        self.tracks_source = source

    def to_dict(self):
        d = asdict(self)
        d["tracks"] = [t.to_dict() for t in self.tracks]
        d["key"] = self.key
        d["completeness"] = self.completeness
        d["returned_track_count"] = self.returned_track_count
        d["streamable_track_count"] = self.streamable_track_count
        d["missing_track_count"] = self.missing_track_count
        return d

    @classmethod
    def from_dict(cls, d):
        fields = {k: d[k] for k in cls.__dataclass_fields__ if k in d and k != "tracks"}
        a = cls(**fields)
        a.tracks = [Track.from_dict(t) for t in d.get("tracks") or []]
        return a


@dataclass
class Playlist:
    id: str
    name: str
    declared_track_count: Optional[int] = None
    tracks: list = field(default_factory=list)
    tracks_loaded: bool = False
    public: Optional[bool] = None
    changed: Optional[str] = None

    def __post_init__(self):
        self.name = clean(self.name)

    @property
    def returned_track_count(self):
        return len(self.tracks)

    def to_dict(self):
        d = asdict(self)
        d["tracks"] = [t.to_dict() for t in self.tracks]
        d["returned_track_count"] = self.returned_track_count
        return d

    @classmethod
    def from_dict(cls, d):
        fields = {k: d[k] for k in cls.__dataclass_fields__ if k in d and k != "tracks"}
        p = cls(**fields)
        p.tracks = [Track.from_dict(t) for t in d.get("tracks") or []]
        return p


# --- builders from source payloads -------------------------------------------------------------

def _num(x):
    try:
        return int(x) if x is not None else None
    except (TypeError, ValueError):
        return None


def track_from_subsonic(s, album_fallback=""):
    """A track that Subsonic returned. Subsonic only lists tracks it can stream."""
    return Track(
        title=s.get("title") or "",
        artist=s.get("artist") or "",
        album=s.get("album") or album_fallback,
        track_number=_num(s.get("track")),
        duration=float(s["duration"]) if s.get("duration") is not None else None,
        streamable=True,
        streamable_reason=R_SUBSONIC,
        subsonic_id=s.get("id"),
        subsonic_album_id=s.get("albumId") or s.get("parent"),
    )


def album_from_subsonic_list_entry(a):
    return Album(
        title=a.get("name") or "",
        artist=a.get("artist") or "",
        subsonic_id=a.get("id"),
        cover_art_id=a.get("coverArt"),
        purchased=a.get("created"),
        declared_track_count=_num(a.get("songCount")),
        sources=["subsonic"],
    )


def tracks_from_subsonic_album(album_payload):
    return [track_from_subsonic(s, album_payload.get("name") or "") for s in album_payload.get("song") or []]


def album_from_feed_item(v):
    """From the web collection feed. `featured_track*` fields are deliberately never read."""
    is_single = v.get("tralbum_type") == "t"
    return Album(
        title=v.get("item_title") or "",
        artist=v.get("band_name") or "",
        kind="single" if is_single else "album",
        bandcamp_id=str(v.get("tralbum_id") or v.get("item_id") or ""),
        bandcamp_url=v.get("item_url") or "",
        purchased=v.get("purchased"),
        is_preorder=bool(v.get("is_preorder")),
        sources=["bandcamp"],
    )


def track_from_tralbum(t, album_title, artist, album_is_preorder):
    """From one data-tralbum `trackinfo` entry. Streamable only if the page itself offers a stream file."""
    file_ = t.get("file")
    has_file = bool(file_) if not isinstance(file_, dict) else any(bool(v) for v in file_.values())
    unreleased = bool(t.get("unreleased_track"))
    if unreleased:
        streamable, reason = False, R_UNRELEASED
    elif t.get("streaming") in (0, False):
        streamable, reason = False, R_DISABLED
    elif has_file:
        streamable, reason = True, R_PAGE_FILE
    else:
        streamable, reason = False, R_NO_FILE
    dur = t.get("duration")
    return Track(
        title=t.get("title") or "",
        artist=t.get("artist") or artist or "",
        album=album_title,
        track_number=_num(t.get("track_num")),
        duration=float(dur) if dur else None,
        streamable=streamable,
        streamable_reason=reason,
        bandcamp_id=str(t.get("track_id") or "") or None,
    )
