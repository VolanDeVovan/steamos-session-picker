.pragma library

// Turning desktop entries into cards.
//
// What a card says is decided here and nowhere else, so that the greeter and
// dev/Preview.qml cannot drift apart. The input is what a session's desktop
// entry actually contains, unmodified:
//
//   { name, comment, file, index }
//
// `index` is the row the session had in SDDM's sessionModel, and sddm.login()
// takes that row number — so it has to survive the sorting below.

// Which of the three drawn icons suits a session. Everything unrecognised is a
// desktop, which is what an unknown session most likely is.
function iconFor(text) {
    var s = String(text).toLowerCase();
    if (/kodi|jellyfin|plex|mpv|media|kino/.test(s))
        return "media";
    if (/game|steam|retro|emulation/.test(s))
        return "game";
    return "desktop";
}

// The one session that is not shown as its entry describes it. Its `Name` is
// "SteamOS (gamescope)", which is the name of the compositor, not of the thing
// the room is looking for: everyone including Valve's own interface calls it
// Game Mode. It is also the entry that goes first on the shelf.
function isGameMode(entry) {
    return /gamescope/.test(String(entry.file) + " " + String(entry.name));
}

function build(raw) {
    var cards = [];
    for (var i = 0; i < raw.length; i++) {
        var entry = raw[i];
        var game = isGameMode(entry);
        cards.push({
            title: game ? "Game Mode" : (entry.name || entry.file),
            subtitle: game ? "Steam" : (entry.comment || entry.file),
            kind: game ? "game" : iconFor(entry.file + " " + entry.name),
            file: entry.file,
            index: entry.index,
            game: game
        });
    }

    // Game Mode leads, everything else keeps the order it arrived in. A stable
    // sort is what makes that true, and Array.prototype.sort has been one since
    // ES2019 — this runs on Qt 6's engine, which is well past that.
    cards.sort(function (a, b) {
        return (b.game ? 1 : 0) - (a.game ? 1 : 0);
    });
    return cards;
}
