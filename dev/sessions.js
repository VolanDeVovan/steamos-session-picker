.pragma library

// The list dev/Preview.qml shows.
//
// On the machine there is no list in this repository at all: the greeter is
// handed SDDM's own sessionModel. These entries are a fixture, not a claim
// about any machine — they exist to give three cards and exercise all three
// icons. Kodi in particular is not a session a stock SteamOS install has.
//
// The shape is a desktop entry as SDDM actually hands it over — see
// ui/entries.js, which is what turns these into cards. `file` is a path
// because that is what the `file` role holds on the machine; a bare name here
// would let the preview agree with a greeter that disagrees.

var sessions = [
    {
        name: "SteamOS (gamescope)",
        comment: "SteamOS Big Picture session",
        file: "/usr/share/wayland-sessions/gamescope-wayland.desktop",
        index: 0
    },
    {
        name: "Plasma (Wayland)",
        comment: "Plasma by KDE",
        file: "/usr/share/wayland-sessions/plasma.desktop",
        index: 1
    },
    {
        name: "Kodi",
        comment: "Media centre",
        file: "/usr/share/wayland-sessions/kodi.desktop",
        index: 2
    }
];
