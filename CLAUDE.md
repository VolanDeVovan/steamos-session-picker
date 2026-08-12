# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

A boot-time **session picker** for SteamOS. Instead of logging straight into
Game Mode, the machine lands in a 10-foot menu and the user picks where to go —
Game Mode, Desktop, or a media session. It is driven from a controller, a TV
remote, a keyboard or a mouse.

The picker is session-agnostic: entries are data, not code. Kodi is the first
media entry wired up, but nothing in the picker is specific to it.

Target: a Valve Steam Machine on stock SteamOS; the same mechanism applies to a
Steam Deck. Development happens on any Linux with a Wayland session — `qml` and
`kwin_wayland` come from the flake, never from the host system.

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
| `ui/` | The QML picker. The session list is discovered on the machine and handed in, so `sessions.js` is only the fallback used when the UI runs on its own; `theme.js` holds the palette. |
| `bin/` | The two shell halves that run on the target: the session entry point and the compositor's session command. Everything allowed to touch the system lives here. |
| `dev/` | Rendered screenshots under `dev/shots/`, for reviewing layout. Never shipped. |
| `docs/` | How the SteamOS side works, what input actually arrives, and development notes. |

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
just check      # shell syntax and layout, no display needed
just shots      # re-render the layout review set into dev/shots/
```

**Nothing here starts a compositor.** The picker's session is only ever run on
the target: an attempt to nest one locally took down the developer's own
session. Layout is checked by rendering to PNG, the rest on the machine. Why
that split is not laziness is in [docs/development.md](docs/development.md).

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
| Choice protocol, dev workflow, screenshots, scaling, HDR | [docs/development.md](docs/development.md) |
