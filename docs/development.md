# Development notes

## What can be checked off the target, and what cannot

At boot the picker is SDDM's greeter, and there is no greeter on a development
machine. Nothing in this repository starts one locally, and nothing starts a
compositor either — an early attempt at that took down the developer's own
session.

| Checked here | How |
|---|---|
| Layout, at any resolution and in any state | rendered to PNG, no display needed |
| Input: keyboard, pointer, controller | the picker as an ordinary window |
| Shell syntax, and that the theme is valid QML | `sh -n`, `qmllint` |
| The greeter, the theme, PAM, the boot into it | a SteamOS VM — [`steamos-vm/`](../steamos-vm/README.md) |
| **Game Mode** | **on the machine.** gamescope wants the Deck's GPU |

```sh
just            # list recipes
just run        # live window
just shot NAME  # one PNG into dev/shots/
just shots      # the whole review set
just check      # syntax, layout, theme
```

## Three files, and only one of them is on the machine

`ui/Picker.qml` is everything drawn. It is a plain `Item` that knows nothing
about SDDM, sessions or the system: it is given a list, it emits an index.

`themes/steamos-session-picker/Main.qml` is the greeter around it — the boot
path, and the only one of the three that runs on a machine. `dev/Preview.qml` is
a window around the same Item, which is how the pixels get reviewed without a
greeter to put them in.

Between them sits `ui/entries.js`, the single place that decides what a session
is called and which icon it gets, so the two cannot drift apart.

There is no shell anywhere in this. The picker used to be a session, and that
needed an entry point, a compositor wrapper, a session lister and a
`PICKER_CHOICE:` line parsed back out of stdout; a greeter needs none of it,
because SDDM already starts sessions.

## What the VM caught that the hardware had not

[`steamos-vm/`](../steamos-vm/README.md) runs the same SteamOS image, and every
one of these cost nothing to find there and would have cost a trip to the
television otherwise:

- **The greeter cannot read a checkout in a home directory.** It runs as user
  `sddm`; `/home/deck` is mode 700. The symptom is a stock login screen saying
  "The current theme cannot be loaded", which names the file but not the reason.
  `install.sh` now asks that account directly.
- **A broken theme is not a brick, and neither is a broken session.** SDDM falls
  back to a working login screen, and a session that fails to start returns to
  the greeter. Both seen; both are why the installer no longer needs the
  three-strikes failsafe the old design carried.
- **The Wayland greeter fails on stock SteamOS and says nothing useful.**
  `HELPER_DISPLAYSERVER_ERROR`, then a silent fallback to X11 — because
  `CompositorCommand` names weston, which is not in the image. Reproduced here
  after being found on the machine.
- **Steam's "Switch to Desktop" still leads to the picker.** `steamosctl
  switch-to-desktop-mode` writes only `Session=`, which an empty `User=`
  outranks, so it lands on the greeter.

Verified there end to end: install from a clean image, reboot, and the machine
comes up in the picker with the session list read off its own disk
([boot](../dev/shots/vm-boot-into-picker.png)). Then driven with the keyboard
into Plasma, with no password.

Two things the VM cannot answer: Game Mode, and anything about the television —
CEC end to end, HDR, the controller's own radio.

### Driving it without a person in front of it

A login screen only answers to input, so `steamos-vm` grew a way to send some:

```sh
./steamos-vm key right right ret     # the guest's own keyboard, through QEMU
./steamos-vm screenshot after.png
```

That is the emulated keyboard, so the keys travel the whole evdev and libinput
path a real one takes. For the other question — whether a device that appears
*after* the greeter is on screen reaches it, which is what the TV remote and a
hotplugged controller both are — a uinput keyboard conjured by root does the
job. See [input.md](input.md).

## Screenshots without stealing the display

`--shot=PATH` makes the picker grab its own scene with `grabToImage()` and quit.
Combined with `QT_QPA_PLATFORM=offscreen` and `QT_QUICK_BACKEND=software` it
renders with no display at all, so layout can be reviewed while someone else is
using the screen. `--size=WxH` checks 4K or 720p, `--select=N` and `--launching`
pin down a state.

## Qt 5 is on the machine too, and it cannot load this

SteamOS ships both Qt runtimes, and the Qt 5 one rejects versionless imports:

```
Picker.qml: Library import requires a version
```

That is why `QtVersion=6` in `metadata.desktop` is load-bearing rather than
decorative — it is what makes SDDM run `sddm-greeter-qt6` instead of the Qt 5
greeter, and getting it wrong is a black screen with a working cursor.
`install.sh` refuses to install if that binary is missing.

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

Session titles are the one thing not under this repository's control — they come
from whatever desktop entries the machine has. They wrap to two lines and elide
after that; the name that set that bound was "Plasma (Wayland)", one character
too many for a card at 720p on a single line. Both names a stock machine offers
are retitled in `ui/entries.js` — Game Mode and Desktop Mode — so the bound now
guards whatever session the machine grows next.

## HDR

The picker renders SDR and asks for nothing else. Qt Quick on Wayland does not
implement `wp_color_management_v1`, and a menu has no use for HDR.

It cannot break HDR for what follows either: SDDM tears the greeter down and the
chosen session sets up its own output state. The visible cost is a TV re-sync —
a second or two of black — when moving from the SDR picker into an HDR session.

## What the greeter does not do, and the old design did

The picker no longer covers the chosen session's own startup. When it was a
resident session on a spare virtual terminal it could hold the screen, show
progress, and swap the display across once Game Mode had drawn. A greeter
cannot: SDDM stops it as part of starting the session, and there is nothing left
to hold anything.

What that machinery bought was covering ~4.5s of Game Mode starting. What it
cost was a whole session — brought up, drawn, torn down — before the picker
appeared at all, an autologin that had to stay on, a spare VT with its own getty,
and a relogin loop whenever any of it failed. The greeter process starts 0.33s
after SDDM does, on the machine, and starts the chosen session directly. The
black gap between the two is real, and it is the same gap SteamOS itself has
when it boots into Game Mode.
