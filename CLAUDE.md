# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

A boot-time **session picker** for SteamOS. Instead of logging straight into
Game Mode, the machine lands in a 10-foot menu and the user picks where to go —
Game Mode, Desktop, or a media session. It is driven from a controller, a TV
remote, a keyboard or a mouse.

It is **SDDM's greeter with a theme**, not a session that runs before the real
one: SDDM already owns the session list, starts sessions, and is what a finished
session returns to. Autologin is off and the passwordless login is a PAM rule
(`nopasswdlogin`), not a bypass.

The picker is session-agnostic: entries are data, not code. Kodi is the first
media entry wired up, but nothing in the picker is specific to it.

Target: a Valve Steam Machine on stock SteamOS; the same mechanism applies to a
Steam Deck. Development happens on any Linux with a Wayland session — `qml`
comes from the flake, never from the host system.

## Design

Built for SteamOS first. The picker appears right before Steam's own Game Mode,
so it has to read as part of that system, not as a foreign app. Follow Steam's
visual language:

- **Steam palette**, defined once in `ui/theme.js`: background `#1b2838` fading
  to `#0e141b`, surfaces around `#2a475e`, accent `#66c0f4`, primary text
  `#c7d5e0`, muted text `#8f98a0`.
- **One accent colour.** Steam does not colour-code entries; everything focused
  is the same blue.
- **Focus the way Big Picture shows it**: a single highlight travels between
  cards, the focused card lifts. Not a thin desktop-style focus outline.
- Rounded corners, generous spacing, text large enough to read from a couch.
- **No custom fonts.** SteamOS has no Motiva Sans; use the system default rather
  than shipping a lookalike.

## Layout

| Directory | What lives there |
|---|---|
| `ui/` | The picker itself, knowing nothing about SDDM. `Picker.qml` is a plain Item handed a list and emitting an index; `entries.js` turns desktop entries into cards; `theme.js` holds the palette. |
| `themes/` | The SDDM theme: `Main.qml` wires SDDM's `sessionModel`, `userModel` and `sddm.login()` to `ui/Picker.qml`. This is the whole boot path — there is no shell in it. |
| `dev/` | Never shipped: `Preview.qml` puts the picker in a window, `sessions.js` is the fixture it shows, `shots/` is the rendered review set. |
| `docs/` | How the SteamOS side works, what input actually arrives, and development notes. |
| `steamos-vm/` | A SteamOS virtual machine, for the parts that can only be tested on the OS itself. Self-contained: it reads nothing outside its own directory. |

`bootstrap.sh` and `install.sh` are the only things that touch a real machine,
and they run there, not from here: the repository is cloned into `/opt` on the
target and that checkout *is* the installation.

## Development

Tasks live in the `justfile`; they expect the dev shell on PATH, which
`nix develop` gives, or direnv loads from `.envrc`.

```sh
nix develop
just            # list recipes
just run        # live window: keyboard, pointer, controller
just check      # shell syntax, layout, theme — no display needed
just shots      # re-render the layout review set into dev/shots/
```

**Nothing here starts a compositor or a greeter.** There is no greeter on a
development machine, and an attempt to nest a compositor locally took down the
developer's own session. Layout is checked by rendering to PNG; the greeter,
PAM and the boot path in `steamos-vm/`, which can be driven without a person in
front of it (`./steamos-vm key right ret`, `screenshot`). Why that split is not
laziness is in [docs/development.md](docs/development.md).

## Conventions

- Code comments in **English**, regardless of the language of the conversation.
- Nothing in the repository hardcodes a host name, address or user: it is meant
  to be published and run by anyone with a Steam Machine.
- No speculative config: every line answers a problem actually observed.
- Anything not verified on real hardware is marked as such, in the file where it
  is claimed.

## Where the details live

| Topic | File |
|---|---|
| How SteamOS decides which session to start, and the pitfalls | [docs/mechanism.md](docs/mechanism.md) |
| Installing on an immutable OS: what persists, the update keep list, how Tailscale and Decky do it | [docs/install.md](docs/install.md) |
| Controller, TV remote, keyboard, mouse — what the picker receives | [docs/input.md](docs/input.md) |
| The two faces, dev workflow, screenshots, scaling, HDR | [docs/development.md](docs/development.md) |
