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

# Phase 7: intercept xdg-open. The plugin runs $OMATIME_OPEN_CMD instead of the real
# browser opener, and this recorder appends the URL it was given to $OMATIME_OPEN_LOG.
# Nothing in the harness can launch a browser.
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
    OMATIME_MPRIS=0 \
    OMATIME_ART_FIXTURE_DIR="$artdir" \
    OMATIME_OPEN_CMD="$work/open-recorder.sh" OMATIME_OPEN_LOG="$work/opened-${phase}.log" \
    timeout 240 quickshell -n -p "$work/shell" 2>&1 || true)
  echo "== $label"
  echo "$out" | grep -E "HARNESS|ERROR" | sed -E 's/\x1b\[[0-9;]*m//g; s/^.*HARNESS /  /'
  local p; p=$(echo "$out" | grep -c "HARNESS PASS")
  passes=$((passes + p))
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

launch "phase 1 (fixture library)" "$home" 1
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

# Phase 7: the six link buttons must have invoked the opener with exactly the verified
# URLs, in spec order. Exact match also proves no other URL was opened. The fixture
# library's meta.user is "fixture-user".
expected_links="https://bandcamp.com
https://bandcamp.com/discover
https://daily.bandcamp.com
https://bandcamp.com/radio
https://bandcamp.com/fixture-user/feed
https://bandcamp.com/fixture-user"
if [ -f "$work/opened-1.log" ] && [ "$(cat "$work/opened-1.log")" = "$expected_links" ]; then
  echo "  PASS xdg-open was called with the six verified URLs, in order"; passes=$((passes + 1))
else
  echo "  FAIL link opener log mismatch:"; sed 's/^/    /' "$work/opened-1.log" 2>/dev/null; fail=1
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
