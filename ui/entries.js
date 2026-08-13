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

// `file` is the **path** SDDM read the entry from, not a bare name:
// "/usr/share/wayland-sessions/plasma.desktop". Everything that matches on a
// file goes through here first — including `hide=` in the theme, which names
// entries the way a person would. Found by putting the raw role on a card in
// the VM, which is also why the fixture in dev/sessions.js carries paths.
function fileName(file) {
    return String(file).split("/").pop();
}

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
    return /gamescope/.test(fileName(entry.file) + " " + String(entry.name));
}

// The same problem at the other end of the shelf. `plasma.desktop` calls itself
// "Plasma (Wayland)" — a desktop environment and a display server, neither of
// which is where the room thinks it is going. SteamOS calls that place Desktop
// Mode, in Steam's own menu and everywhere else, so the card says what the rest
// of the machine says.
//
// Matched on the file name rather than on `Name`, which SDDM hands over
// translated: on a Russian machine it arrives as "Плазма (Wayland)".
// Anchored on the two entries a stock machine has, not on a prefix: a machine
// that grows `plasma-bigscreen.desktop` should get a card of its own rather
// than a second one calling itself Desktop Mode.
function isDesktopMode(entry) {
    return /^plasma(x11)?\.desktop$/.test(fileName(entry.file));
}

function titleFor(entry) {
    if (isGameMode(entry))
        return "Game Mode";
    if (isDesktopMode(entry))
        // `plasmax11.desktop` is Desktop Mode's legacy twin and is hidden by
        // default — see `hide=` in the theme's theme.conf. It keeps the suffix
        // so that a machine which brings it back has two cards it can tell
        // apart rather than two that read the same.
        return /x11/.test(fileName(entry.file)) ? "Desktop Mode (X11)" : "Desktop Mode";
    return entry.name || fileName(entry.file);
}

function build(raw) {
    var cards = [];
    for (var i = 0; i < raw.length; i++) {
        var entry = raw[i];
        var game = isGameMode(entry);
        cards.push({
            title: titleFor(entry),
            subtitle: game ? "Steam" : (entry.comment || fileName(entry.file)),
            // The name, not the path: a session dropped in below
            // /opt/steamos-session-picker would otherwise match "steam" and
            // come out wearing the Game Mode icon.
            kind: game ? "game" : iconFor(fileName(entry.file) + " " + entry.name),
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
