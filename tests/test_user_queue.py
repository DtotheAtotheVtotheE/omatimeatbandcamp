"""Unit tests for the session-only user queue model (UserQueue.js).

The queue model is plain ES5 with no Qt imports, and Service.qml imports this
same file. Node runs the exact source; each unittest case maps to one focused
model scenario so a regression names the broken semantic.
"""

import os
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "tests", "user_queue.test.js")
NODE = shutil.which("node")

CASES = [
    "ordering-and-duplicates",
    "album-add-skips-unstreamable",
    "unstreamable-never-queued",
    "drain-resume-point",
    "drain-at-context-end-stops",
    "clear-vs-new-context",
    "previous-history",
    "play-at-drops-ahead",
    "clear-keeps-current-playback",
]


@unittest.skipUnless(NODE, "node is required to run the shared UserQueue.js model")
class UserQueueModel(unittest.TestCase):
    def run_case(self, name):
        result = subprocess.run(
            [NODE, SCRIPT, name],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            result.returncode,
            0,
            "UserQueue case failed:\n" + result.stdout + result.stderr,
        )
        self.assertIn("PASS " + name, result.stdout)

    def test_ordering_play_next_vs_append_and_duplicates(self):
        self.run_case("ordering-and-duplicates")

    def test_album_add_skips_unstreamable_with_counts(self):
        self.run_case("album-add-skips-unstreamable")

    def test_unstreamable_tracks_are_never_queued(self):
        self.run_case("unstreamable-never-queued")

    def test_drain_resumes_after_the_interrupted_track(self):
        self.run_case("drain-resume-point")

    def test_drain_at_context_end_stops_without_replaying(self):
        self.run_case("drain-at-context-end-stops")

    def test_new_context_clears_and_same_context_keeps(self):
        self.run_case("clear-vs-new-context")

    def test_previous_steps_through_actual_history(self):
        self.run_case("previous-history")

    def test_playing_a_queue_row_drops_it_and_everything_ahead(self):
        self.run_case("play-at-drops-ahead")

    def test_clear_keeps_current_queued_track_playing(self):
        self.run_case("clear-keeps-current-playback")


if __name__ == "__main__":
    unittest.main()
