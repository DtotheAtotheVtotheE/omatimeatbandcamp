// Session-only user queue model for v3.4.
//
// This file is deliberately free of Qt/QML imports so the same code that the
// service runs can be unit-tested under Node (tests/test_user_queue.py). The
// state is immutable: every operation returns a new object, which keeps QML
// property bindings reactive.
//
// State:
//   pending      tracks waiting to play, in added order
//   current      the queued track currently playing, or null
//   resumeIndex  context queue index to resume at when the queue drains, or -1
//   history      tracks actually played during this queue takeover, newest last:
//                {track, user} entries; user=false means the interrupted context track
//
// The user queue is separate from the service's context `queue`/`queueIndex`.
// Queued tracks never enter the context queue, so the context's shuffle order
// is preserved underneath the queue.

function emptyState() {
  return { pending: [], current: null, resumeIndex: -1, history: [] }
}

function copyState(s) {
  return {
    pending: (s && s.pending ? s.pending : []).slice(),
    current: s ? s.current : null,
    resumeIndex: s ? s.resumeIndex : -1,
    history: (s && s.history ? s.history : []).slice()
  }
}

// Only streamable tracks may ever enter the queue. This is the one gate used by
// Play Next, Add to Queue and album/playlist adds.
function canQueue(track) {
  return !!track && track.streamable !== false
}

// A different album/playlist/search context clears the queue; another track in
// the same context leaves it alone. An empty key is not a real context.
function isNewContext(playingKey, nextKey) {
  return !(nextKey !== "" && nextKey === playingKey)
}

// The context track AFTER the interrupted one, or -1 when there is none. The
// interrupted track is never selected again.
function resumeIndexAfter(contextIndex, contextLength) {
  if (contextIndex < 0 || contextLength <= 0 || contextIndex >= contextLength) return -1
  return contextIndex < contextLength - 1 ? contextIndex + 1 : -1
}

// Play Next: insert at the FRONT. Duplicates are allowed.
function enqueueFront(state, track) {
  var n = copyState(state)
  if (!canQueue(track)) return { state: n, added: 0, skipped: 1 }
  n.pending = [track].concat(n.pending)
  return { state: n, added: 1, skipped: 0 }
}

// Add to Queue: append at the END. Duplicates are allowed.
function enqueueTrack(state, track) {
  var n = copyState(state)
  if (!canQueue(track)) return { state: n, added: 0, skipped: 1 }
  n.pending = n.pending.concat([track])
  return { state: n, added: 1, skipped: 0 }
}

// Add many tracks in order, skipping unstreamable ones. Returns the counts the
// UI reports ("Added N ... · M skipped").
function enqueueTracks(state, tracks) {
  var n = copyState(state)
  var added = 0, skipped = 0
  var list = tracks || []
  for (var i = 0; i < list.length; i++) {
    if (canQueue(list[i])) { n.pending.push(list[i]); added++ }
    else skipped++
  }
  return { state: n, added: added, skipped: skipped }
}

// Empty the pending queue without touching playback. A queued track that is
// currently playing keeps playing; only what has not started is dropped.
function clearPending(state) {
  var n = copyState(state)
  n.pending = []
  return n
}

function removeAt(state, index) {
  var n = copyState(state)
  if (index >= 0 && index < n.pending.length) n.pending.splice(index, 1)
  return n
}

// Stop treating the current queued track as queue playback while keeping the
// pending list. Used when the user starts another track in the SAME context.
function releaseCurrent(state) {
  var n = copyState(state)
  n.current = null
  n.resumeIndex = -1
  n.history = []
  return n
}

// Play pending[index] immediately, dropping it and everything ahead of it.
// Returns the new state and the track to play. History records the item that
// was actually playing (the interrupted context track, or the previous queued
// track) so Previous can step back through real playback.
function startAt(state, index, contextIndex, contextLength, contextTrack, recordHistory) {
  var n = copyState(state)
  if (index < 0 || index >= n.pending.length) return { state: n, track: null, changed: false }
  var track = n.pending[index]
  if (!canQueue(track)) return { state: n, track: null, changed: false }

  n.pending = n.pending.slice(index + 1)
  if (!n.current) {
    // First takeover: remember the context position after the interrupted
    // track and make that track the Previous target.
    if (n.resumeIndex < 0) n.resumeIndex = resumeIndexAfter(contextIndex, contextLength)
    if (contextTrack) n.history = n.history.concat([{ track: contextTrack, user: false }])
  } else if (recordHistory !== false) {
    n.history = n.history.concat([{ track: n.current, user: true }])
  }
  n.current = track
  return { state: n, track: track, changed: true }
}

function startHead(state, contextIndex, contextLength, contextTrack) {
  return startAt(state, 0, contextIndex, contextLength, contextTrack)
}

// The current queued track ended (or Next went past the last one) with no
// pending tracks left. Resume at the saved context index, or stop when the
// interrupted track was the last one in the context.
function drain(state) {
  var n = copyState(state)
  if (n.resumeIndex >= 0) {
    var target = n.resumeIndex
    n.pending = []
    n.current = null
    n.resumeIndex = -1
    n.history = []
    return { state: n, contextIndex: target, stopped: false }
  }
  // No context track after the interrupted one: keep the last played track as
  // the footer's current item, but playback is over.
  n.resumeIndex = -1
  return { state: n, contextIndex: -1, stopped: true }
}

// Previous from a queued track. Pops the last actually-played item. When it is
// a queued track, that becomes current again and the track we left goes back to
// the front of pending. When it is the interrupted context track, the service
// returns to the context at that track (contextIndex is resolved there because
// the context queue may have been reordered by shuffle).
function previous(state) {
  var n = copyState(state)
  if (!n.current || n.history.length === 0) return { state: n, track: null, user: false, changed: false }
  var entry = n.history.pop()
  n.pending = [n.current].concat(n.pending)
  if (entry.user) {
    n.current = entry.track
    return { state: n, track: entry.track, user: true, changed: true }
  }
  n.current = null
  n.resumeIndex = -1
  return { state: n, track: entry.track, user: false, changed: true }
}
