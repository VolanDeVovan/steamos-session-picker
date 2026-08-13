# How SteamOS picks a session, and how the picker gets in front

Everything here was read out of the `sddm` and `steamos-manager` sources and
confirmed on a live Steam Machine (SteamOS holo, sddm 0.21.0-6, kwin 6.4.3) or
in [`steamos-vm/`](../steamos-vm/README.md), which runs the same image. Which
one is said in each place.

## The short version

SDDM is already a session picker. It is resident between sessions, it owns the
list of sessions, it starts them, and it is what a finished session returns to.
On SteamOS it is simply never seen, because autologin takes the machine straight
into Game Mode.

So the picker is not a session that runs before the real one. It is **SDDM's own
greeter, with a theme**:

```
sddm.service ──▶ greeter: kwin_wayland + sddm-greeter-qt6 + this theme
                    │
                    └── sddm.login(user, "", session) ──▶ the chosen session
```

Nothing of ours runs as root, nothing runs between the greeter and the session,
and there is no way back to a black screen: SDDM tears the greeter down only
once the session has started, and if the session dies the greeter is what
returns.

## Who decides

**SDDM config merge** (`sddm.conf(5)`, `src/common/ConfigReader.cpp`):

```
/usr/lib/sddm/sddm.conf.d/*   ->   /etc/sddm.conf.d/*   ->   /etc/sddm.conf
```

Inside a directory files are read alphabetically and the last one wins;
`/etc/sddm.conf` beats everything, and **does not exist on this machine** —
checked, on hardware and in the VM. Merging is per key, not per file.

**What ships on the device**, `/etc/sddm.conf.d/steamos.conf`:

```ini
[General]
DisplayServer=wayland
InputMethod=qtvirtualkeyboard

[Autologin]
Relogin=true
Session=gamescope-wayland.desktop
User=deck
```

**What steamos-manager writes** (`session.rs:313-335`) — only ever the
`Session=` key, never `User=`:

| File | Written by |
|---|---|
| `zz-steamos-autologin.conf` | `set-default-login-mode`, `set-default-desktop-session` |
| `zzt-steamos-temp-login.conf` | any `switch-to-*`, one shot |

**What this project writes**, `/etc/sddm.conf.d/zzz-steamos-session-picker.conf`.
The name sorts after both of Valve's files, so it is the last word without any
of them being edited:

```ini
[Autologin]
User=

[General]
DisplayServer=wayland
InputMethod=

[Wayland]
CompositorCommand=kwin_wayland --no-lockscreen --no-global-shortcuts --locale1

[Theme]
ThemeDir=/opt/steamos-session-picker/themes
Current=steamos-session-picker
```

An empty `User=` is the whole of "turn autologin off". `Session=` is deliberately
left alone: steamos-manager keeps writing it, and with autologin off it is a
default rather than a decision — which is why **Steam's own "Switch to Desktop"
still works and now leads here**, verified in the VM.

## The four keys, and why each one is there

**`User=`** — with no user there is no autologin, and SDDM shows the greeter.

**`CompositorCommand=`** — the one line that decides whether any of this is
possible. SDDM's default is `weston --shell=kiosk` and **SteamOS does not ship
weston**. Left alone, the Wayland greeter fails with
`HELPER_DISPLAYSERVER_ERROR` and SDDM silently falls back to `DisplayServer=x11`,
which works but starts an X server for a menu. kwin is in the image and is what
the desktop session uses anyway. Measured on the machine: the greeter process is
up **0.33s** after SDDM starts, against 1.37–1.75s for the whole session path it
replaces. In the VM the same step takes 0.31s and the theme's own load adds
about 1.4s on top — software rendering, so that second figure means nothing for
a machine with a GPU and has not been measured on one.

**`InputMethod=`** — stock SteamOS loads qtvirtualkeyboard into the greeter, for
typing passwords. This greeter never asks for one.

**`ThemeDir=`** — SDDM's theme directory is a setting, so the theme can live in
the checkout in `/opt` and nothing has to be written to the read-only rootfs. No
overlay mount, no session entry, no `steamosctl` call: the previous design
needed all three and none of them survive into this one.

## Logging in without a password

Autologin is off, so SDDM authenticates. It must therefore be told that this
account may log in at the login screen without a password — and told in the one
place that decides such things, which is PAM.

One line at the top of `/etc/pam.d/sddm`:

```
auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin
```

plus a `nopasswdlogin` group with the account in it. This is the mechanism
Debian and Ubuntu ship for exactly this purpose, and it is deliberately not any
of the alternatives:

| Instead of | Why not |
|---|---|
| `pam_permit.so` in the sddm stack | anyone at all, including accounts that should not |
| `user = deck` | hardcodes a user; this repository names none |
| clearing the account password | weakens `sudo` and ssh, which are not the login screen |
| leaving autologin on | then there is no greeter, and no picker |

What it changes, exactly: **at SDDM, a member of that group logs in without a
password.** `sudo`, ssh and everything else are untouched — they read their own
PAM stacks, and `system-auth` is not modified. The machine already logged this
account in with no password at all before, from autologin; this moves that trust
into PAM, where it can be read, scoped and revoked.

Verified in the VM, from the greeter, on a `deck` account that has a password
set:

```
pam_succeed_if(sddm:auth): requirement "user ingroup nopasswdlogin" was met by user "deck"
Authentication for user  "deck"  successful
```

`/etc/pam.d` is **not** on SteamOS's atomic-update keep list, so `install.sh`
adds `/etc/atomic-update.conf.d/steamos-session-picker.conf` naming that file.
`/etc/group` is on the default list already. See [install.md](install.md).

## What the theme is handed

A theme is a directory with `metadata.desktop` and a `Main.qml`, loaded by
`sddm-greeter-qt6` — the same Qt 6 QML the picker was already written in.
`QtVersion=6` in the metadata is what selects that binary; the Qt 5 greeter
cannot load versionless imports.

| Name | What it is |
|---|---|
| `sessionModel` | every session in `SessionDir`, with `name`, `comment`, `file` — `file` being the **path** it was read from, and `name` translated |
| `userModel` | the accounts offered, and `lastUser` |
| `sddm.login(user, password, index)` | authenticate and start, by row in `sessionModel` |
| `sddm.suspend()`, `sddm.reboot()` | and `canSuspend`/`canReboot`, which are logind's answer to whether the greeter may — so a machine that would refuse never shows the button |
| `config.*` | `theme.conf`, and `theme.conf.user` beside it |

`sessionModel` is the whole of session discovery, and Game Mode is in it like
anything else — `/usr/share/wayland-sessions/gamescope-wayland.desktop` is an
ordinary entry. Only its *name* is special-cased, in `ui/entries.js`: the entry
calls itself "SteamOS (gamescope)", which is the compositor, not the thing
anyone is looking for.

The desktop is special-cased the same way, and one entry is dropped. A stock
machine has **two KDE sessions** — `plasma.desktop` (Wayland) and
`plasmax11.desktop` — and the machine's own answer is the first:
`steamosctl get-default-desktop-session` returns `plasma.desktop` on 3.8.14 with
nothing configured, so that is the built-in default, not a leftover choice. The
X11 entry is the fallback for hardware a Steam Machine is not, and it is hidden
by `hide=` in the theme's `theme.conf`. The one that stays is titled **Desktop
Mode**, which is what Steam's own menu calls the place it goes.

Worth knowing while reading old scripts: `/usr/bin/steamos-session-select` is
deprecated but still shipped "for Steam client compatibility", and in it a bare
`plasma` still means **X11** — `steamosctl switch-to-desktop-mode
plasmax11.desktop`. The Wayland default is reached as `plasma-wayland`.

A C++ model cannot be indexed from QML, so `Main.qml` reads it through two
invisible `Repeater`s and `itemAt()`. That is the reason they are there.

## The screen, when nobody picks anything

Game Mode leaves idling to Steam, Desktop Mode to powerdevil — which runs as
part of the Plasma session and therefore not at a login screen. So the greeter
was the one place on the machine with **no opinion at all**: a picker nobody
answered lit a static picture on a television until someone came back, and
never slept.

powerdevil is in the image as an ordinary D-Bus service, so it goes where cecd
went — an instance in the greeter's own session, one symlink into that
account's user units. Two things it is handed inside Plasma and has to be given
here, both in `plasma-powerdevil.service.d/greeter.conf`:

| | |
|---|---|
| `Environment=WAYLAND_DISPLAY=wayland-0` | Plasma exports its session environment into the user manager; the greeter does not. Without it powerdevil loads the xcb plugin, finds no display and aborts — `SIGABRT`, three times, then systemd gives up on it. |
| a `.path` unit, wanted instead of the service | `default.target` is reached before kwin has made the socket, so what the session wants is the **watch**, not the daemon: `PathExists=%t/wayland-0` starts `plasma-powerdevil.service` when the compositor arrives and re-arms when it goes, which is what the end of every greeter looks like. Nothing polls, nothing fails on purpose, and a machine where no Wayland greeter ever appears — the silent X11 fallback in [development.md](development.md) — simply never starts it. Measured across a cold boot and a session round trip: `NRestarts=0`. |

The profile in `~sddm/.config/powerdevilrc` names two numbers — screen off at
five minutes, sleep at fifteen — and inherits everything else from SteamOS's
own `/etc/xdg/powerdevilrc`. That file is worth reading before changing any of
this: it is where `AutoSuspendAction` is read from rather than guessed (`1` is
sleep, `0` is do nothing, the same enumeration the power button uses), and it
sets `AutoSuspendIdleTimeoutSec=300` for a Deck on battery while leaving a
machine on AC awake. A living room is not a handheld, so the picker sleeps.

**None of this reaches the sessions it starts**, which is the question worth
asking of anything hung off the greeter. It is all in user `sddm`'s session, and
that session ends when a card is chosen: checked on a Steam Machine mid-game and
in the VM the moment a session came up — `user@969.service` inactive, no process
running as `sddm` at all, and the only `PowerDevil` inhibitor on the machine
belonging to uid 1000. Game Mode, Desktop Mode and anything added later keep
whatever power management they came with.

Verified in the VM: the screen goes off on time, any key brings it back — and
the key that wakes it is swallowed, so nothing is launched by someone reaching
for the pad in the dark. The machine then really does suspend, QEMU reporting
`paused (suspended)`, and it resumes. Checked on the second greeter as well as
the first, because that is the one a finished session returns to: after
`systemctl restart sddm` the picker blanks and wakes exactly as before, with
`NRestarts` one higher than it was.

**What the VM cannot answer**, and what has to be tried on a Steam Machine:
whether the picture comes back after that resume, and whether a controller
wakes the machine at all. In the VM it does not — `virtio_gpu` fails its
pageflip after S3 and takes kwin down with it, which the kernel itself calls a
driver bug. Game Mode sleeps and wakes from the pad on the real thing, and wake
sources are the kernel's business rather than Steam's, so it should hold here
too. Until it is tried: the power button is the way back, and
`PICKER_SLEEP=0 ./install.sh` is the way to say the picker may not sleep.

## Pitfalls

- **The greeter runs as user `sddm`, not as you.** A checkout in a home
  directory is mode 700 and the theme simply cannot be read; the only symptom is
  a stock login screen saying "The current theme cannot be loaded". `/opt` is
  world-readable and is where the installer puts it. `install.sh` asks the
  account itself — `sudo -u sddm test -r …` — rather than guessing from the path.
- **A broken theme is not a brick.** SDDM falls back to a working login screen
  and prints the error on it. Seen in the VM, deliberately.
- **`file` in `sessionModel` is a path, not a name.** It arrives as
  `/usr/share/wayland-sessions/plasma.desktop`, and nothing says so — a match
  against `plasma.desktop` simply never fires, silently. It made `hide=` a key
  that did nothing until the VM was asked to put the raw value on a card.
  Everything matching on a file goes through `Entries.fileName()` now.
- **A session that fails to start is not a loop either.** SDDM returns to the
  greeter. `Relogin=true` only ever applied to autologin, which is now off — the
  failure mode that shaped the previous design no longer exists.
- **`/etc/sddm.conf.d/*` is on the default atomic-update keep list**
  (`/usr/lib/rauc/atomic-update-keep.conf`), so the drop-in survives OS updates
  with nothing extra registered. `/etc/pam.d/*` is not, hence the keep file.

## Not verified on hardware yet

The greeter, its 0.33s start and the missing weston were all measured on a Steam
Machine. **This theme has not been run on one** — everything above about the
theme, the PAM line and the boot into it was verified in `steamos-vm/`, on the
same SteamOS image. What a VM cannot answer is in
[development.md](development.md).
