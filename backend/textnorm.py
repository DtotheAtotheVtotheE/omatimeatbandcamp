"""Text decoding and cross-source normalisation.

`clean()` is for display text: HTML entities decoded (repeatedly, so
`&amp;amp;` also resolves), whitespace collapsed, nothing else changed.

`norm()` / `album_key()` are for matching only and are never shown to users.
"""
import html
import re
import unicodedata

_WS = re.compile(r"\s+")
_NON_ALNUM = re.compile(r"[\W_]+", re.UNICODE)


def clean(s):
    if s is None:
        return ""
    s = str(s)
    for _ in range(4):
        d = html.unescape(s)
        if d == s:
            break
        s = d
    return _WS.sub(" ", s).strip()


def norm(s):
    """Case-, accent- and punctuation-insensitive form of `s`."""
    s = clean(s).replace("&", " and ")
    s = unicodedata.normalize("NFKD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = s.casefold()
    out = _NON_ALNUM.sub(" ", s).strip()
    if out:
        return _WS.sub(" ", out)
    # titles made only of symbols (e.g. "???") would all collide on ""
    return _WS.sub(" ", clean(s).casefold())


def album_key(artist, title):
    return f"{norm(artist)}|{norm(title)}"
