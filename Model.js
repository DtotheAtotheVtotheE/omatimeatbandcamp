function bestStream(fileObj) {
  if (!fileObj || typeof fileObj !== "object") return null;
  const keys = ["mp3-v0", "mp3-320", "mp3-128", "aac-hi", "flac", "wav", "aiff-lossless"];
  for (var i = 0; i < keys.length; i++) {
    if (fileObj.hasOwnProperty(keys[i]) && fileObj[keys[i]]) return fileObj[keys[i]];
  }
  for (var k in fileObj) {
    if (fileObj.hasOwnProperty(k) && typeof fileObj[k] === "string" && fileObj[k].indexOf("http") === 0) return fileObj[k];
  }
  return null;
}

function fisherYates(arr) {
  var a = arr.slice();
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1));
    var tmp = a[i]; a[i] = a[j]; a[j] = tmp;
  }
  return a;
}

function flattenTracks(collection, playlists) {
  var tracks = [];
  if (collection) {
    for (var i = 0; i < collection.length; i++) {
      var alb = collection[i];
      var tlist = alb.tracks || [];
      for (var j = 0; j < tlist.length; j++) {
        var t = tlist[j];
        tracks.push({
          title: t.title || "",
          artist: t.artist || alb.artist || "",
          album: t.album || alb.title || "",
          albumUrl: t.albumUrl || alb.albumUrl || alb.item_url || "",
          trackUrl: t.trackUrl || "",
          streamUrl: t.streamUrl || null,
          duration: t.duration || 0
        });
      }
    }
  }
  if (playlists) {
    for (var p = 0; p < playlists.length; p++) {
      var pl = playlists[p];
      var pt = pl.tracks || [];
      for (var k = 0; k < pt.length; k++) {
        var tt = pt[k];
        tracks.push({
          title: tt.title || "",
          artist: tt.artist || "",
          album: tt.album || "",
          albumUrl: tt.albumUrl || "",
          trackUrl: tt.trackUrl || "",
          streamUrl: tt.streamUrl || null,
          duration: tt.duration || 0,
          fromPlaylist: pl.name || ""
        });
      }
    }
  }
  return tracks;
}

function searchIndex(collection, playlists, query) {
  var q = (query || "").toLowerCase();
  var results = {albums: [], tracks: []};
  if (!q) return results;
  if (collection) {
    for (var i = 0; i < collection.length; i++) {
      var alb = collection[i];
      var hay = (alb.title + " " + (alb.artist||"")).toLowerCase();
      if (hay.indexOf(q) >= 0) results.albums.push(alb);
      var tlist = alb.tracks || [];
      for (var j = 0; j < tlist.length; j++) {
        var t = tlist[j];
        var th = (t.title + " " + (t.artist||alb.artist||"") + " " + (t.album||alb.title||"")).toLowerCase();
        if (th.indexOf(q) >= 0) results.tracks.push(t);
      }
    }
  }
  if (playlists) {
    for (var p = 0; p < playlists.length; p++) {
      var pl = playlists[p];
      var pt = pl.tracks || [];
      for (var k = 0; k < pt.length; k++) {
        var tt = pt[k];
        var th = (tt.title + " " + (tt.artist||"") + " " + (tt.album||"") + " " + (pl.name||"")).toLowerCase();
        if (th.indexOf(q) >= 0) results.tracks.push(tt);
      }
    }
  }
  return results;
}
