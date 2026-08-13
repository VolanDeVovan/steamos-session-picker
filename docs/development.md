# Development notes

## What can be checked off the target, and what cannot

The picker's session is a compositor, and a compositor is not something to start
on a working desktop — an early attempt at it took down the developer's own
session. So nothing in this repository launches one locally.

| Checked here | How |
|---|---|
| Layout, at any resolution and in any state | rendered to PNG, no display needed |
| Input: keyboard, pointer, controller | the picker as an ordinary window |
| Shell syntax | `sh -n` |
| **Everything else** | **on the machine, through `install.sh`** |

That last row is not laziness: the two bugs found so far were both in how kwin
hosts the picker, and neither could have been caught by any local stand-in — see
"What kwin does to its session" below.

```sh
just            # list recipes
just run        # live window
just shot NAME  # one PNG into dev/shots/
just shots      # the whole review set
just check      # syntax and layout
```

## Screenshots without stealing the display

`--shot=PATH` makes the picker grab its own scene with `grabToImage()` and quit.
Combined with `QT_QPA_PLATFORM=offscreen` and `QT_QUICK_BACKEND=software` it
renders with no display at all, so layout can be reviewed while someone else is
using the screen. `--size=WxH` checks 4K or 720p, `--select=N` and `--launching`
pin down a state.

## The choice protocol

The QML half never runs a command. It prints one line:

```
PICKER_CHOICE:game-mode
PICKER_CHOICE:desktop:kodi.desktop
PICKER_CHOICE:none
```

`bin/compositor-session` captures that line and writes it to `$PICKER_CHOICE_FILE`.
`bin/steamos-session-picker` reads the file once the compositor is gone, validates
the session name against `[A-Za-z0-9._-]`, and calls `steamosctl`.

Nothing in the shell learns any session's name: it understands the two target
shapes and nothing else.

## Where the session list comes from

`bin/list-sessions` builds it at session start by reading the session
directories, plus the desktop entry each name resolves to — `Name=` for the title, `Comment=` for the subtitle, falling back
to the file name. Installing a new session therefore makes it appear in the
picker on the next boot, with nothing edited.

Two entries are special. **Game Mode** is written by hand, because
steamos-manager refuses any session whose name contains `gamescope` and so never
lists it; it has its own verb instead. And the **picker itself** is filtered out,
so it cannot offer to launch itself.

It reads the filesystem rather than asking `steamos-manager`, which reads the
same directories. Asking the daemon is a dependency that failed exactly where it
mattered: at boot the picker starts within a second of the display manager, the
answer came back empty, and the menu showed its built-in fallback list — offering
a session the machine does not have. The filesystem is always ready.

Sessions whose name contains `gamescope` are skipped, because
`steamos-manager` refuses them and a menu should not offer what cannot be
started. So is the picker's own entry.

## The cursor starts where you left it

After a choice is made it is written to
`~/.local/state/steamos-session-picker/last-choice`, and the next time the menu
opens the cursor is already on it. Power on, press once, gone. A cancellation is
not a preference and is not recorded.

Icons are guessed from the name — kodi/jellyfin/plex/mpv read as media,
game/steam/retro as a gamepad, everything else as a desktop, which is what an
unknown session most likely is.

### Why the list arrives as a command-line argument

The list is handed to the UI as one JSON argument, `--sessions=[…]`. That is not
elegant, but the alternatives were measured, not assumed:

| Channel | Result |
|---|---|
| `XMLHttpRequest` on a `file://` URL | **does not work.** Synchronous hangs the process; asynchronous never fires the callback. Tested both. |
| Environment variable | QML has no way to read one without a C++ shim |
| Standard input | QML cannot read it |
| A generated `.js` that QML imports | imports resolve relative to the QML file at load time, so it means writing into the checkout and dirtying the git tree |
| One JSON argument | works, `JSON.parse` is built in, and a single argument may be 128 KiB — about 1300 sessions |

The only real costs are that the list shows up in `ps` output, which contains
nothing private, and that quoting is our problem — hence `json_escape` in
`bin/compositor-session`, checked against a session named `Kodi "Media" Center`.

Without the argument the UI falls back to `ui/sessions.js`, which is what keeps
`just run` working on a machine that has no `steamosctl` at all.

### Two qml runtimes, and only one of them works

SteamOS ships both, and `/usr/bin/qml` is **qt5-declarative's**. It cannot load
this UI at all — versionless imports are a Qt 6 feature:

```
Picker.qml: Library import requires a version
```

The Qt 6 runtime is `/usr/lib/qt6/bin/qml`, with a `qml6` alias.
`bin/qml-runtime` resolves it so both halves of the project agree, and
`install.sh` reports which one it found. On the first hardware run this was a
black screen with a working cursor: kwin was up, the UI never started.

### What kwin does to its session

Two behaviours shaped the design above. Both were observed on kwin's virtual
backend, so both want re-checking on the target — but the code is written to
survive either way.

**kwin mangles arguments after a second `--`.** Given

```sh
kwin_wayland -- qml Picker.qml -- --fullscreen
```

the qml runtime receives no file at all and dies with `No files specified`. That
was the original entry point, which would have meant a black screen on the first
real boot — and with `Relogin=true`, an endless relogin loop. Hence the session
being a script, `bin/compositor-session`, passed as a single argument.

**kwin does not forward its session's output.** A line printed by the picker
never reaches the process that started kwin, so it cannot be read from there.
Hence the capture living one level down, inside the session script, where `qml`
is a direct child — and the answer leaving through a file.

**kwin does not stop when its session exits.** It keeps holding the screen for
as long as it is left alone, so something has to signal it. It stops on SIGTERM
immediately.

**And the session is not kwin's child.** KWin 6 starts it through the systemd
user manager, so `$PPID` inside the session script is systemd. Signalling the
parent therefore cannot work — an early attempt at it, run where the parent was
a login shell rather than a compositor, killed an unrelated session. The
compositor is found instead by the command line only it has:

```sh
pgrep -f "kwin_wayland .*compositor-session"
```

### Everything above was a black screen

Each of those faults looks identical from the sofa: the picker's own log,
written before the output is filtered, is what separated them. It is worth
keeping for that reason alone.

### Qt logging goes to journald

`console.log()` from QML produced no output on stderr at all, not even through
`console.error()`: Qt built with journald support routes logging there instead.
`QT_FORCE_STDERR_LOGGING=1` restores stderr, and the entry point exports it.
Where Qt logs to stderr anyway, the variable does nothing.

## Layout scaling

Nothing is expressed in raw pixels. `Picker.qml` computes

```qml
readonly property real u: Math.min(width / 1920, height / 1080)
```

and every size is a multiple of it, so the same design holds from 1280x720 to
3840x2160. Verified by rendering all three.

Output scaling does not matter either: at 4K with scale 2 the surface is
1920x1080 logical, `u` becomes 1, and the result is the same layout drawn with
twice the pixels.

## HDR

The picker renders SDR and asks for nothing else. Qt Quick on Wayland does not
implement `wp_color_management_v1`, and a menu has no use for HDR.

It cannot break HDR for what follows either: the picker exits, its compositor
exits, and only then does `steamosctl` start the next session, which sets up its
own output state. The visible cost is a TV re-sync — a second or two of black —
when moving from the SDR picker into an HDR session.
