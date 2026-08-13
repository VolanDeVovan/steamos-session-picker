.pragma library

// The list dev/Preview.qml shows.
//
// On the machine there is no list in this repository at all: the greeter is
// handed SDDM's own sessionModel. These entries are a fixture, not a claim
// about any machine — they exist to give three cards and exercise all three
// icons. Kodi in particular is not a session a stock SteamOS install has.
//
// The shape is a desktop entry as it is actually read — see ui/entries.js,
// which is what turns these into cards.

var sessions = [
    {
        name: "SteamOS (gamescope)",
        comment: "SteamOS Big Picture session",
        file: "gamescope-wayland.desktop",
        index: 0
    },
    {
        name: "Plasma",
        comment: "Plasma by KDE",
        file: "plasma.desktop",
        index: 1
    },
    {
        name: "Kodi",
        comment: "Media centre",
        file: "kodi.desktop",
        index: 2
    }
];
