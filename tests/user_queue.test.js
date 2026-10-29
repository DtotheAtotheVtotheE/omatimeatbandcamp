#!/usr/bin/env node
// Unit tests for UserQueue.js (the exact model Service.qml imports).
// Run directly: node tests/user_queue.test.js [case]
// Run through unittest: python3 -m unittest tests.test_user_queue
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "UserQueue.js"), "utf8")
const sandbox = {}
vm.runInNewContext(source + "\nthis.api = { emptyState, canQueue, isNewContext, resumeIndexAfter, enqueueFront, enqueueTrack, enqueueTracks, clearPending, removeAt, releaseCurrent, startAt, startHead, drain, previous, identityOf, serialize, resolveEntry, restorePending }\n", sandbox)
const Q = sandbox.api

function track(uid, title, streamable) {
  return { uid: uid, title: title || uid, streamable: streamable !== false }
}
function streamable(uid, title) { return track(uid, title, true) }
function unstreamable(uid, title) { return track(uid, title, false) }
function libraryTrack(uid, title, extra) {
  var t = { uid: uid, title: title || uid, artist: "Artist", album: "Album", streamable: true }
  if (extra) for (var k in extra) t[k] = extra[k]
  return t
}
function names(list) { return list.map(function(t) { return t.uid }) }
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b)
  if (x !== y) throw new Error((msg || "mismatch") + ": " + x + " != " + y)
}
function ok(v, msg) { if (!v) throw new Error(msg || "expected truthy") }

const cases = {
  "ordering-and-duplicates": function() {
    var s = Q.emptyState()
    var a = streamable("a"), b = streamable("b")
    s = Q.enqueueTrack(s, a).state
    s = Q.enqueueTrack(s, b).state
    s = Q.enqueueTrack(s, a).state
    eq(names(s.pending), ["a", "b", "a"], "Add to Queue appends and keeps duplicates")
    s = Q.enqueueFront(s, b).state
    eq(names(s.pending), ["b", "a", "b", "a"], "Play Next inserts at the front and keeps duplicates")
  },

  "album-add-skips-unstreamable": function() {
    var s = Q.emptyState()
    var out = Q.enqueueTracks(s, [streamable("1"), unstreamable("2"), streamable("3"), unstreamable("4")])
    eq(names(out.state.pending), ["1", "3"], "only streamable tracks are appended, in order")
    eq([out.added, out.skipped], [2, 2], "counts added and skipped")
    var none = Q.enqueueTracks(Q.emptyState(), [unstreamable("u1"), unstreamable("u2")])
    eq([none.added, none.skipped], [0, 2], "all-unstreamable album reports 0 added / 2 skipped")
    eq(names(none.state.pending), [], "nothing queued")
  },

  "unstreamable-never-queued": function() {
    var s = Q.emptyState()
    var front = Q.enqueueFront(s, unstreamable("x"))
    var back = Q.enqueueTrack(s, unstreamable("y"))
    eq([front.added, front.skipped], [0, 1], "Play Next refuses an unstreamable track")
    eq([back.added, back.skipped], [0, 1], "Add to Queue refuses an unstreamable track")
    eq(names(front.state.pending), [], "Play Next queue stays empty")
    eq(names(back.state.pending), [], "Add to Queue queue stays empty")
  },

  "drain-resume-point": function() {
    // Context [c0,c1,c2,c3], interrupted at c1. Queue [a,b].
    var s = Q.emptyState()
    s = Q.enqueueTracks(s, [streamable("a"), streamable("b")]).state
    var first = Q.startHead(s, 1, 4, streamable("c1", "Interrupted"))
    s = first.state
    eq(first.track.uid, "a", "queue head plays first")
    eq(s.resumeIndex, 2, "resume point is the track AFTER the interrupted one")
    eq(names(s.pending), ["b"], "played head was removed")
    var second = Q.startHead(s, 1, 4, streamable("c1", "Interrupted"))
    s = second.state
    eq(second.track.uid, "b", "second queued track plays next")
    eq(names(s.pending), [], "queue is empty after the last head")
    var d = Q.drain(s)
    eq(d.stopped, false, "drain resumes the context")
    eq(d.contextIndex, 2, "drain resumes at c2 (interrupted c1 is not replayed)")
    eq(d.state.current, null, "queue playback state is cleared on resume")
    eq(d.state.history.length, 0, "context previous is pure again after resume")
  },

  "drain-at-context-end-stops": function() {
    // Interrupted track is the last context track: there is no track after it.
    var s = Q.enqueueTrack(Q.emptyState(), streamable("a")).state
    s = Q.startHead(s, 2, 3, streamable("c2")).state
    eq(s.resumeIndex, -1, "no resume point after the last context track")
    eq(Q.resumeIndexAfter(2, 3), -1, "resumeIndexAfter handles the last track")
    var d = Q.drain(s)
    eq(d.stopped, true, "the queue stops instead of replaying the interrupted track")
    eq(d.contextIndex, -1, "no context target")
  },

  "clear-vs-new-context": function() {
    ok(!Q.isNewContext("album:a", "album:a"), "same album is not a new context")
    ok(Q.isNewContext("album:a", "album:b"), "another album is a new context")
    ok(Q.isNewContext("album:a", "playlist:p"), "another playlist/search is a new context")
    ok(Q.isNewContext("", "album:a"), "starting from no context is a new context")
    var s = Q.enqueueTracks(Q.emptyState(), [streamable("a"), streamable("b")]).state
    s = Q.startHead(s, 1, 4, streamable("c1")).state
    // Same-context start keeps the pending queue but leaves queue playback.
    var same = Q.releaseCurrent(s)
    eq(names(same.pending), ["b"], "same-context start keeps the pending queue")
    eq(same.current, null, "same-context start stops treating the old queued track as current")
    // New context clears it.
    eq(names(Q.emptyState().pending), [], "new context starts from an empty queue")
  },

  "previous-history": function() {
    // Context [c0,c1,c2,c3], interrupted at c1. Queue [a,b].
    var s = Q.enqueueTracks(Q.emptyState(), [streamable("a"), streamable("b")]).state
    s = Q.startHead(s, 1, 4, streamable("c1", "Interrupted")).state
    s = Q.startHead(s, 1, 4, streamable("c1", "Interrupted")).state
    eq(s.current.uid, "b", "on b")
    eq(s.history.map(function(e) { return e.track.uid + (e.user ? ":u" : ":c") }).join(","),
       "c1:c,a:u", "history records the interrupted context track then a")
    var p = Q.previous(s)
    s = p.state
    eq(p.track.uid, "a", "Previous from a queued track goes to the previously played queued track")
    eq(names(s.pending), ["b"], "the track left by Previous returns to the queue head")
    p = Q.previous(s)
    s = p.state
    eq(p.user, false, "Previous from the first queued track targets the context")
    eq(p.track.uid, "c1", "it is the interrupted context track")
    eq(s.current, null, "the service returns to context playback")
    eq(names(s.pending), ["a", "b"], "both queued tracks are pending again")
    // No history -> no change (pure context Previous is handled by the service).
    eq(Q.previous(s).changed, false, "previous outside queue playback is unchanged")
  },

  "play-at-drops-ahead": function() {
    var s = Q.enqueueTracks(Q.emptyState(), [streamable("a"), streamable("b"), streamable("c")]).state
    var r = Q.startAt(s, 1, 0, 4, streamable("c0"))
    eq(r.track.uid, "b", "double-clicking a queue row plays that track")
    eq(names(r.state.pending), ["c"], "everything ahead of it and the track itself are dropped")
  },

  "clear-keeps-current-playback": function() {
    var s = Q.enqueueTracks(Q.emptyState(), [streamable("a"), streamable("b")]).state
    s = Q.startHead(s, 0, 3, streamable("c0")).state
    var c = Q.clearPending(s)
    eq(names(c.pending), [], "Clear empties Up Next")
    eq(c.current.uid, "a", "Clear does not stop the queued track that is already playing")
    var removed = Q.removeAt(Q.enqueueTracks(Q.emptyState(), [streamable("a"), streamable("b")]).state, 0)
    eq(names(removed.pending), ["b"], "Remove from queue removes only that row")
  },

  "persistence-round-trip": function() {
    var a = libraryTrack("alb#0", "One", { subsonicId: "t:1", streamUrl: "https://secret.example/stream?token=CREDENTIAL", coverArtId: "cover-1" })
    var b = libraryTrack("alb#1", "Two", { bandcampId: "bc-2" })
    var s = Q.enqueueTracks(Q.emptyState(), [a, b]).state
    var saved = Q.serialize(s)
    var text = JSON.stringify({ version: 1, pending: saved })
    ok(text.indexOf("secret.example") < 0 && text.indexOf("CREDENTIAL") < 0 && text.indexOf("streamUrl") < 0,
       "persisted entries carry no stream URL or credential")
    ok(text.indexOf("cover-1") < 0 && text.indexOf("coverArtId") < 0, "persisted entries carry no cover id")
    var restored = Q.restorePending(JSON.parse(text).pending, [a, b])
    eq(names(restored), ["alb#0", "alb#1"], "a saved queue restores in order")
    eq([restored[0].title, restored[0].artist, restored[0].album], ["One", "Artist", "Album"],
       "restored entries are the live library tracks, metadata intact")
  },

  "persistence-duplicates-and-order": function() {
    var a = libraryTrack("alb#0", "One", { subsonicId: "t:1" })
    var b = libraryTrack("alb#1", "Two", { subsonicId: "t:2" })
    var s = Q.enqueueTracks(Q.emptyState(), [a, b, a, b, a]).state
    var saved = JSON.parse(JSON.stringify(Q.serialize(s)))
    var restored = Q.restorePending(saved, [a, b])
    eq(names(restored), ["alb#0", "alb#1", "alb#0", "alb#1", "alb#0"],
       "duplicates and their order survive a save/load round-trip")
  },

  "restore-drops-deleted": function() {
    var a = libraryTrack("alb#0", "One", { subsonicId: "t:1" })
    var b = libraryTrack("alb#1", "Two", { subsonicId: "t:2" })
    var c = libraryTrack("alb#2", "Three", { subsonicId: "t:3" })
    var saved = Q.serialize(Q.enqueueTracks(Q.emptyState(), [a, b, c]).state)
    // b's album was removed from the library since the queue was saved.
    var restored = Q.restorePending(saved, [a, c])
    eq(names(restored), ["alb#0", "alb#2"], "an entry whose track is gone is dropped silently")
  },

  "restore-drops-unstreamable": function() {
    var a = libraryTrack("alb#0", "One", { subsonicId: "t:1" })
    var b = libraryTrack("alb#1", "Two", { subsonicId: "t:2", streamable: false })
    var saved = Q.serialize(Q.enqueueTracks(Q.emptyState(), [a, b]).state)
    var restored = Q.restorePending(saved, [a, b])
    eq(names(restored), ["alb#0"], "an entry that is no longer streamable is dropped silently")
  },

  "restore-rejects-stale-uid": function() {
    // Same uid index, different track: the metadata guard must not restore it.
    var saved = Q.serialize(Q.enqueueTrack(Q.emptyState(), libraryTrack("alb#0", "Old Name")).state)
    var recycled = libraryTrack("alb#0", "Different Song")
    eq(names(Q.restorePending(saved, [recycled])), [],
       "a uid that now points at different metadata is not restored")
    // A rebuilt library with a new uid still resolves by exact metadata.
    var moved = libraryTrack("alb#9", "Old Name")
    eq(names(Q.restorePending(saved, [moved])), ["alb#9"],
       "the same track under a new uid still restores by metadata")
  }
}

const requested = process.argv[2]
const run = requested ? [[requested, cases[requested]]] : Object.keys(cases).map(function(k) { return [k, cases[k]] })
let failed = 0
for (const [name, fn] of run) {
  if (!fn) { console.log("FAIL " + name + " (unknown case)"); failed++; continue }
  try { fn(); console.log("PASS " + name) }
  catch (e) { console.log("FAIL " + name + " — " + e.message); failed++ }
}
process.exit(failed === 0 ? 0 : 1)
