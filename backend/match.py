"""Match the web collection list against the Subsonic album list.

Stage 1: albums by normalised key (`textnorm.album_key`). Keys can repeat (two
         entries "Frog Myst - Kuiper Belt" exist on both sides), so entries are
         paired *within* a key by closest purchase time, falling back to order.
Stage 2: web single-track items (`kind == "single"`). Subsonic exposes a
         single-track purchase as its parent album holding just the purchased
         track(s), so these are matched by normalised track title against the
         tracks of still-unmatched Subsonic albums.

Nothing is dropped: every web item and every Subsonic album ends up in the
result, matched or not, and the MatchReport says which and why.
"""
import logging
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime

from .model import Album
from .textnorm import norm

log = logging.getLogger("omatime.match")


def _ts(s):
    try:
        return datetime.strptime(s, "%d %b %Y %H:%M:%S GMT").timestamp()
    except (TypeError, ValueError):
        return None


def _pair_within_key(web, sub):
    """Greedy closest-timestamp pairing. Returns (pairs, web_left, sub_left)."""
    web, sub = list(web), list(sub)
    pairs = []
    while web and sub:
        best = None
        for wi, w in enumerate(web):
            for si, s in enumerate(sub):
                tw, ts = _ts(w.purchased), _ts(s.purchased)
                d = abs(tw - ts) if tw is not None and ts is not None else 1e18
                if best is None or d < best[0]:
                    best = (d, wi, si)
        _, wi, si = best
        pairs.append((web.pop(wi), sub.pop(si)))
    return pairs, web, sub


def _merge(web, sub):
    """Web display text/ids + Subsonic ids/counts. Web `is_preorder` and `purchased` are kept."""
    web.subsonic_id = sub.subsonic_id
    web.cover_art_id = sub.cover_art_id
    web.declared_track_count = sub.declared_track_count
    web.sources = ["bandcamp", "subsonic"]
    return web


@dataclass
class MatchReport:
    web_items: int = 0
    subsonic_albums: int = 0
    matched_by_key: int = 0
    duplicate_keys_paired: int = 0
    single_items_matched_by_track: int = 0
    single_parent_albums: int = 0
    unresolved_singles: list = field(default_factory=list)
    web_only: list = field(default_factory=list)          # web albums with no Subsonic counterpart
    subsonic_only: list = field(default_factory=list)     # Subsonic albums with no web counterpart
    merged_albums: int = 0

    @property
    def web_items_matched(self):
        return self.matched_by_key + self.single_items_matched_by_track

    @property
    def web_coverage_pct(self):
        return round(100.0 * self.web_items_matched / self.web_items, 1) if self.web_items else 0.0

    def summary(self):
        return (f"match coverage: {self.web_items_matched}/{self.web_items} web items matched to Subsonic "
                f"({self.web_coverage_pct}%): {self.matched_by_key} by album key "
                f"({self.duplicate_keys_paired} paired inside a duplicated key), "
                f"{self.single_items_matched_by_track} single-track items via {self.single_parent_albums} parent albums; "
                f"{len(self.web_only)} web-only albums, {len(self.unresolved_singles)} unresolved singles, "
                f"{len(self.subsonic_only)} Subsonic-only albums; {self.merged_albums} albums in the merged library")

    def to_dict(self):
        return {
            "web_items": self.web_items, "subsonic_albums": self.subsonic_albums,
            "matched_by_key": self.matched_by_key, "duplicate_keys_paired": self.duplicate_keys_paired,
            "single_items_matched_by_track": self.single_items_matched_by_track,
            "single_parent_albums": self.single_parent_albums,
            "web_only": self.web_only, "unresolved_singles": self.unresolved_singles,
            "subsonic_only": self.subsonic_only, "merged_albums": self.merged_albums,
            "web_coverage_pct": self.web_coverage_pct, "summary": self.summary(),
        }


def match_albums(web_albums, sub_albums, sub_tracks_for=None):
    """Return (merged_albums, MatchReport).

    web_albums:     Album objects built from the web feed (kind "album" or "single").
    sub_albums:     Album objects built from getAlbumList2.
    sub_tracks_for: callable(subsonic_id) -> list[Track]; used only for stage 2.
    """
    rep = MatchReport(web_items=len(web_albums), subsonic_albums=len(sub_albums))
    wk, sk = defaultdict(list), defaultdict(list)
    for a in web_albums:
        if a.kind == "album":
            wk[a.key].append(a)
    for a in sub_albums:
        sk[a.key].append(a)

    merged, matched_sub = [], set()
    web_left = []
    for key, ws in wk.items():
        ss = sk.get(key, [])
        pairs, w_left, _s_left = _pair_within_key(ws, ss)
        if len(ws) > 1 and ss:
            rep.duplicate_keys_paired += len(pairs)
        for w, s in pairs:
            merged.append(_merge(w, s))
            matched_sub.add(id(s))
            rep.matched_by_key += 1
        web_left += w_left

    # stage 2: single-track web items
    singles = [a for a in web_albums if a.kind == "single"]
    unmatched_sub = [s for s in sub_albums if id(s) not in matched_sub]
    title_index = defaultdict(list)       # normalised track title -> [Subsonic album]
    if singles and sub_tracks_for:
        for s in unmatched_sub:
            for t in sub_tracks_for(s.subsonic_id) or []:
                title_index[norm(t.title)].append(s)
    parents = {}
    for single in singles:
        cands = title_index.get(norm(single.title), [])
        if cands:
            parent = cands[0]
            if len(cands) > 1:
                log.warning("single %r matches %d Subsonic albums; using %s", single.title, len(cands), parent.subsonic_id)
            matched_sub.add(id(parent))
            if id(parent) not in parents:
                parents[id(parent)] = parent
                parent.kind = "single"
                parent.sources = ["bandcamp", "subsonic"]
                parent.bandcamp_id = single.bandcamp_id
                parent.bandcamp_url = single.bandcamp_url
                parent.web_item_ids = []
            parents[id(parent)].web_item_ids.append(single.bandcamp_id)
            rep.single_items_matched_by_track += 1
        else:
            rep.unresolved_singles.append({"artist": single.artist, "title": single.title, "bandcamp_id": single.bandcamp_id})
            merged.append(single)
    for p in parents.values():
        merged.append(p)
    rep.single_parent_albums = len(parents)

    for w in web_left:
        rep.web_only.append({"artist": w.artist, "title": w.title, "bandcamp_id": w.bandcamp_id,
                             "is_preorder": w.is_preorder})
        merged.append(w)
    for s in sub_albums:
        if id(s) not in matched_sub:
            rep.subsonic_only.append({"artist": s.artist, "title": s.title, "subsonic_id": s.subsonic_id})
            merged.append(s)

    rep.merged_albums = len(merged)
    log.info(rep.summary())
    return merged, rep
