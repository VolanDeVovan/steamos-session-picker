.pragma library

// Fallback session list, used only when nothing passed --sessions=.
//
// On the machine the list is discovered at session start by bin/picker-session,
// from `steamosctl get-valid-desktop-sessions` plus the desktop entries it names
// — so installing a new session makes it appear here by itself, with no edit.
// What remains here is what the UI shows when run on its own, during
// development. These entries are a fixture, not a claim about any machine:
// they exist to give three cards and exercise all three icons. Kodi in
// particular is not a session a stock SteamOS install has.
//
// target, printed verbatim for bin/steam-session-picker, which is the only half
// allowed to run commands:
//   "game-mode"                 hand back to Steam's Game Mode
//   "desktop:<name>.desktop"    any session registered with steamos-manager
//
// kind picks an icon from SessionIcon.qml: game | desktop | media.

var sessions = [
    {
        title: "Game Mode",
        subtitle: "Steam",
        kind: "game",
        target: "game-mode"
    },
    {
        title: "Desktop",
        subtitle: "Plasma",
        kind: "desktop",
        target: "desktop:plasma.desktop"
    },
    {
        title: "Kodi",
        subtitle: "Media centre",
        kind: "media",
        target: "desktop:kodi.desktop"
    }
];
