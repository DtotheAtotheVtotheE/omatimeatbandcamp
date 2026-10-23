#!/usr/bin/env bash
# QML interaction tests for the plugin window (Panel.qml + Service.qml + BcButton.qml).
#
#   tests/qml/run.sh
#
# Builds a throwaway copy of the Omarchy shell under a temp dir, swaps the layer-shell
# KeyboardPanel for a plain-Item stub (offscreen has no PanelWindow backend), symlinks this
# plugin in, and runs the tests with a FAKE $HOME holding a decoy cookies.txt, so logout and
# refresh are exercised for real without touching your files.
#
# NOT covered (stubbed): the real KeyboardPanel's click-outside-to-close and window focus
# handling. Those are the shell's own code and are unchanged by the plugin.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../.." && pwd)
shell_src=${OMARCHY_PATH:-/usr/share/omarchy}/shell
work=$(mktemp -d "${TMPDIR:-/tmp}/omatime-qml.XXXXXX")
trap 'rm -rf "$work"' EXIT

cp -r "$shell_src" "$work/shell"
cp "$here/KeyboardPanel.stub.qml" "$work/shell/Ui/KeyboardPanel.qml"
cp "$here/shell.qml" "$work/shell/shell.qml"
ln -s "$plugin" "$work/shell/plug"

home="$work/home"
mkdir -p "$home/.cache/omatimeatbandcamp"
for f in collection.json playlists.json; do
  [ -f "$HOME/.cache/omatimeatbandcamp/$f" ] && cp "$HOME/.cache/omatimeatbandcamp/$f" "$home/.cache/omatimeatbandcamp/$f"
done
echo "DECOY-NOT-A-REAL-COOKIE" > "$home/.cache/omatimeatbandcamp/cookies.txt"

out=$(HOME="$home" OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" QT_QPA_PLATFORM=offscreen \
  timeout 90 quickshell -n -p "$work/shell" 2>&1 || true)
echo "$out" | grep -E "HARNESS|ERROR" | sed -E 's/\x1b\[[0-9;]*m//g; s/^.*HARNESS /  /'

fail=0
echo "$out" | grep -q "HARNESS FAILS=0" || fail=1
echo "$out" | grep -q "ERROR" && fail=1
if [ -e "$home/.cache/omatimeatbandcamp/cookies.txt" ]; then
  echo "  FAIL confirmed logout did not delete the (decoy) cookies.txt"; fail=1
else
  echo "  PASS confirmed logout deleted the (decoy) cookies.txt"
fi
[ "$fail" -eq 0 ] && echo "QML tests: OK" || echo "QML tests: FAILED"
exit "$fail"
