#!/usr/bin/env bash
# QML interaction tests for the plugin window (Panel.qml + Service.qml + BcButton.qml).
#
#   tests/qml/run.sh
#
# Builds a throwaway copy of the Omarchy shell under a temp dir, swaps the layer-shell
# KeyboardPanel for a plain-Item stub (offscreen has no PanelWindow backend), symlinks this
# plugin in, and runs tests/qml/shell.qml with a FAKE $HOME, so logout, refresh and the
# persisted UI choices are exercised for real without touching your files.
#
# Three launches:
#   1. phase 1: all behaviour, against the synthetic library in tests/qml/fixtures/
#   2. phase 2: relaunch on the same fake HOME; the sort/filter choices from phase 1 must come back
#   3. real:    invariants against YOUR library cache (~/.cache/omatimeatbandcamp/library/library.json),
#               read-only copy; skipped if it does not exist. Skip with REAL=0.
#
# NOT covered (stubbed): the real KeyboardPanel's click-outside-to-close and window focus
# handling. Those are the shell's own code and are unchanged by the plugin.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../.." && pwd)
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
work=$(mktemp -d "${TMPDIR:-/tmp}/omatime-qml.XXXXXX")
cleanup() {
  # mpv is spawned detached; kill only this run's sockets (never the user's player).
  pkill -f "input-ipc-server=$work/mpv-" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

cp -r "$omarchy/shell" "$work/shell"
cp "$here/KeyboardPanel.stub.qml" "$work/shell/Ui/KeyboardPanel.qml"
cp "$here/shell.qml" "$work/shell/shell.qml"
ln -s "$plugin" "$work/shell/plug"

fail=0
passes=0

# Phase 7 (v3): intercept xdg-open. The plugin runs $OMATIME_OPEN_CMD instead of the
# real browser opener, and this recorder appends the URL it was given to $OMATIME_OPEN_LOG.
# Nothing in the harness can launch a browser. v3 keeps only the Collection link,
# now reached through the gear menu.
cat > "$work/open-recorder.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$OMATIME_OPEN_LOG"
EOF
chmod +x "$work/open-recorder.sh"

launch() {  # launch <label> <home> <phase>
  local label=$1 home=$2 phase=$3 out
  # Own mpv socket (never the user's real one) and a null audio sink: the harness must
  # not query or play through the live player.
  out=$(HOME="$home" HARNESS_PHASE="$phase" OMARCHY_PATH="$omarchy" QT_QPA_PLATFORM=offscreen \
    OMATIME_MPV_SOCK="$work/mpv-${phase}.sock" OMATIME_MPV_FLAGS="--ao=null" OMATIME_PLUGIN_DIR="$plugin" \
    OMATIME_MPRIS=0 HARNESS_TONE="$work/tone.wav" \
    OMATIME_ART_FIXTURE_DIR="$artdir" \
    OMATIME_OPEN_CMD="$work/open-recorder.sh" OMATIME_OPEN_LOG="$work/opened-${phase}.log" \
    timeout 240 quickshell -n -p "$work/shell" 2>&1 || true)
  echo "== $label"
  echo "$out" | grep -E "HARNESS|ERROR" | sed -E 's/\x1b\[[0-9;]*m//g; s/^.*HARNESS /  /'
  local p; p=$(echo "$out" | grep -c "HARNESS PASS")
  passes=$((passes + p))
  last_out="$out"
  echo "$out" | grep -q "HARNESS FAILS=0" || fail=1
  echo "$out" | grep -q "ERROR" && fail=1
  echo "  -> $label: $p checks passed"
}

home="$work/home"
mkdir -p "$home/.cache/omatimeatbandcamp/library"
cp "$here/fixtures/library.json" "$home/.cache/omatimeatbandcamp/library/library.json"
echo "DECOY-NOT-A-REAL-COOKIE" > "$home/.cache/omatimeatbandcamp/cookies.txt"

# Phase 6 art fixtures: two clearly different shapes/colours so a replacement is measurable.
# The service maps cover ids to <dir>/<id>.jpg when OMATIME_ART_FIXTURE_DIR is set, so the
# harness exercises the real backend downscale path without any network or credentials.
artdir="$work/art"
mkdir -p "$artdir"
convert -size 300x120 xc:'#c33' "$artdir/fx-a.jpg" 2>/dev/null
convert -size 90x260 xc:'#3c3' "$artdir/fx-b.jpg" 2>/dev/null

# First-track regression fixture: a real local audio file for the isolated mpv.
# Generated with the stdlib (no ffmpeg dependency); --ao=null means it is silent.
python3 - "$work/tone.wav" <<'PY'
import math, struct, sys, wave
rate, secs = 8000, 10
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", int(9000 * math.sin(2 * math.pi * 440 * n / rate)))
                           for n in range(rate * secs)))
PY

launch "phase 1 (fixture library)" "$home" 1

# v3.5.4: the bold SVG mark must render in the theme accent at full strength,
# from the saved real-size PNG (not just from the QML binding). Crop the art's
# exact panel rect and require pixels equal to Color.accent; also prove no baked
# white. A second probe measures the rendered ink centroid against the column.
shot=/tmp/omatime-v354-header.png
accent=$(printf '%s\n' "$last_out" | sed -n 's/.*HARNESS v3\.5\.4 pixels: accent=\(#[0-9A-Fa-f]\{6\}\).*/\1/p' | head -1)
rect=$(printf '%s\n' "$last_out" | sed -n 's/.*HARNESS v3\.5\.4 pixels: accent=#[0-9A-Fa-f]\{6\} art=\([0-9][0-9]*,[0-9][0-9]*,[0-9][0-9]*,[0-9][0-9]*\).*/\1/p' | head -1)
column=$(printf '%s\n' "$last_out" | sed -n 's/.*HARNESS v3\.5\.4 pixels: .*column=\([0-9][0-9]*,[0-9][0-9]*,[0-9][0-9]*,[0-9][0-9]*\).*/\1/p' | head -1)
if [ -n "$accent" ] && [ -n "$rect" ] && [ -f "$shot" ]; then
  probe=$(python3 - "$shot" "$accent" "$rect" <<'PY'
import subprocess, sys
shot, accent, rect = sys.argv[1:4]
x, y, w, h = (int(v) for v in rect.split(","))
# Inset the art rect so the probe can only see the mark itself.
x, y, w, h = x + 3, y + 3, w - 6, h - 6
raw = subprocess.check_output(["convert", shot, "-crop", f"{w}x{h}+{x}+{y}", "+repage",
                               "-depth", "8", "rgb:-"], stderr=subprocess.DEVNULL)
if len(raw) != w * h * 3:
    print(f"wrong crop size: {len(raw)} bytes for {w}x{h}")
    sys.exit(1)
pixels = [raw[i:i + 3] for i in range(0, len(raw), 3)]
from collections import Counter
bg = Counter(pixels).most_common(1)[0][0]
want = tuple(bytes.fromhex(accent[1:]))
ink = [p for p in pixels if max(p) >= max(bg) + 30]
peak = max(ink, key=sum) if ink else bg
exact = sum(1 for p in pixels if tuple(p) == want)
pure_white = sum(1 for p in pixels if p[0] >= 250 and p[1] >= 250 and p[2] >= 250)
over_accent = sum(1 for p in pixels if max(p) > max(want) + 2)
print(f"rect={x},{y},{w},{h} accent={accent} inkPixels={len(ink)} exactAccentPixels={exact} "
      f"peak=#{peak[0]:02x}{peak[1]:02x}{peak[2]:02x} pureWhitePixels={pure_white} "
      f"overAccentPixels={over_accent}")
sys.exit(0 if len(ink) >= 150 and exact >= 1 and tuple(peak) == want and pure_white == 0 and
         (want == (255, 255, 255) or over_accent == 0) else 1)
PY
)
  if [ $? -eq 0 ]; then
    echo "  PASS the rendered bold cat paths are the theme accent at full strength, with no baked white ($probe)"; passes=$((passes + 1))
  else
    echo "  FAIL the rendered bold cat paths do not match the theme accent ($probe)"; fail=1
  fi
else
  echo "  FAIL cat-SVG accent probe missing (accent='$accent' rect='$rect' shot='$shot')"; fail=1
fi

if [ -n "$accent" ] && [ -n "$column" ] && [ -f "$shot" ]; then
  centroid=$(python3 - "$shot" "$accent" "$column" <<'PY'
import subprocess, sys
from collections import Counter
shot, accent, column = sys.argv[1:4]
x, y, w, h = (int(v) for v in column.split(","))
# Inset 2 px to exclude the panel's own border from the ink weighting.
inset = 2
x0, y0, w0, h0 = x + inset, y + inset, w - 2 * inset, h - 2 * inset
raw = subprocess.check_output(["convert", shot, "-crop", f"{w0}x{h0}+{x0}+{y0}", "+repage",
                               "-depth", "8", "rgb:-"], stderr=subprocess.DEVNULL)
if len(raw) != w0 * h0 * 3:
    print(f"wrong column crop: {len(raw)} bytes for {w0}x{h0}")
    sys.exit(1)
pixels = [raw[i:i + 3] for i in range(0, len(raw), 3)]
bg = Counter(pixels).most_common(1)[0][0]
want = tuple(bytes.fromhex(accent[1:]))
den = sum(want[i] - bg[i] for i in range(3))
if den == 0:
    print("accent and background are identical")
    sys.exit(1)
sx = sy = sw = 0.0
for yy in range(h0):
    for xx in range(w0):
        p = pixels[yy * w0 + xx]
        a = sum(p[i] - bg[i] for i in range(3)) / den
        if a > 0.02:
            a = max(0.0, min(1.0, a))
            sx += (x0 + xx) * a
            sy += (y0 + yy) * a
            sw += a
if sw == 0:
    print("no ink found in the cat column")
    sys.exit(1)
cx, cy = sx / sw, sy / sw
col_cx, col_cy = x + w / 2, y + h / 2
dx, dy = cx - col_cx, cy - col_cy
print(f"column={x},{y},{w},{h} centroid={cx:.2f},{cy:.2f} target={col_cx:.2f},{col_cy:.2f} "
      f"error={dx:.2f},{dy:.2f} inkWeight={sw:.1f}")
sys.exit(0 if sw >= 100 and abs(dx) <= 3 and abs(dy) <= 3 else 1)
PY
)
  if [ $? -eq 0 ]; then
    echo "  PASS the rendered bold cat's ink centroid is centred in the column ($centroid)"; passes=$((passes + 1))
  else
    echo "  FAIL the rendered bold cat's ink centroid is not centred in the column ($centroid)"; fail=1
  fi
else
  echo "  FAIL cat-column centroid probe missing (accent='$accent' column='$column' shot='$shot')"; fail=1
fi

if [ -e "$home/.cache/omatimeatbandcamp/cookies.txt" ]; then
  echo "  FAIL confirmed logout did not delete the (decoy) cookies.txt"; fail=1
else
  echo "  PASS confirmed logout deleted the (decoy) cookies.txt"; passes=$((passes + 1))
fi
ui_p1=$(cat "$home/.local/state/omatimeatbandcamp/ui.json" 2>/dev/null)
echo "  ui.json on disk after phase 1: $ui_p1"
if echo "$ui_p1" | grep -q '"sortMode":"title"' && echo "$ui_p1" | grep -q '"hidePreorders":true'; then
  echo "  PASS phase 1's sort + filter choices were written to ui.json"; passes=$((passes + 1))
else
  echo "  FAIL phase 1's choices were not written to ui.json"; fail=1
fi

# Phase 7 (v3/v3.5.1): the single Collection menu item must have invoked the opener with exactly
# the verified URL. Exact match also proves no other URL was opened. The fixture
# library's meta.user is "fixture-user".
expected_links="https://bandcamp.com/fixture-user"
if [ -f "$work/opened-1.log" ] && [ "$(cat "$work/opened-1.log")" = "$expected_links" ]; then
  echo "  PASS xdg-open was called with only the Collection URL"; passes=$((passes + 1))
else
  echo "  FAIL link opener log mismatch:"; sed 's/^/    /' "$work/opened-1.log" 2>/dev/null; fail=1
fi

# v3: the companion bar-art widget is gone from the plugin, and nothing references it.
if [ ! -e "$plugin/bar-art" ] && ! grep -q "bar-art/ArtWidget" "$plugin/Panel.qml" "$plugin/Service.qml" "$plugin/README.md"; then
  echo "  PASS bar-art widget removed from the plugin and no source references it"; passes=$((passes + 1))
else
  echo "  FAIL bar-art widget or a source reference still exists"; fail=1
fi

# v3.5.1: naming sweep. Functional ids stay lowercase; only text/product names change.
old_product_spelling="Band""Camp"
if ! grep -rq "$old_product_spelling" --exclude-dir=.git --exclude-dir=__pycache__ "$plugin"; then
  echo "  PASS no remaining old product spelling anywhere in the repo text"; passes=$((passes + 1))
else
  echo "  FAIL old product spelling still present:"; grep -rln "$old_product_spelling" --exclude-dir=.git --exclude-dir=__pycache__ "$plugin" | sed 's/^/    /'; fail=1
fi

# Phase 8: the keyboard is panel-scoped. No global shortcut type may appear in the
# plugin, and no Hyprland binding is registered (the harness cannot see Hyprland;
# the source check is the enforceable half).
if grep -qE "GlobalShortcut|Shortcut[[:space:]]*\{" "$plugin/Panel.qml" "$plugin/Service.qml"; then
  echo "  FAIL plugin registers a global/window Shortcut (keys must be panel-scoped)"; fail=1
else
  echo "  PASS no global/window shortcut API in the plugin (keys are panel-scoped)"; passes=$((passes + 1))
fi

launch "phase 2 (relaunch, same HOME)" "$home" 2
ui_after=$(cat "$home/.local/state/omatimeatbandcamp/ui.json" 2>/dev/null)
echo "  ui.json on disk after phase 2: $ui_after"
if echo "$ui_after" | grep -q '"hidePreorders":false' && echo "$ui_after" | grep -q '"sortMode":"title"'; then
  echo "  PASS phase 2's change reached the file on disk (read by the shell script, not by the QML probe)"; passes=$((passes + 1))
else
  echo "  FAIL phase 2's change did not reach ui.json"; fail=1
fi

real_lib="${HOME}/.cache/omatimeatbandcamp/library/library.json"
if [ "${REAL:-1}" != "0" ] && [ -f "$real_lib" ]; then
  rhome="$work/realhome"
  mkdir -p "$rhome/.cache/omatimeatbandcamp/library"
  cp "$real_lib" "$rhome/.cache/omatimeatbandcamp/library/library.json"
  launch "real-data smoke (your library cache)" "$rhome" real
else
  echo "== real-data smoke skipped (no $real_lib, or REAL=0)"
fi

echo "QML checks passed in total: $passes"
[ "$fail" -eq 0 ] && echo "QML tests: OK" || echo "QML tests: FAILED"
exit "$fail"
