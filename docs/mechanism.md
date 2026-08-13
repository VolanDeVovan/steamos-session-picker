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
| `sessionModel` | every session in `SessionDir`, with `name`, `comment`, `file` |
| `userModel` | the accounts offered, and `lastUser` |
| `sddm.login(user, password, index)` | authenticate and start, by row in `sessionModel` |
| `config.*` | `theme.conf`, and `theme.conf.user` beside it |

`sessionModel` is the whole of session discovery, and Game Mode is in it like
anything else — `/usr/share/wayland-sessions/gamescope-wayland.desktop` is an
ordinary entry. Only its *name* is special-cased, in `ui/entries.js`: the entry
calls itself "SteamOS (gamescope)", which is the compositor, not the thing
anyone is looking for.

A C++ model cannot be indexed from QML, so `Main.qml` reads it through two
invisible `Repeater`s and `itemAt()`. That is the reason they are there.

## Pitfalls

- **The greeter runs as user `sddm`, not as you.** A checkout in a home
  directory is mode 700 and the theme simply cannot be read; the only symptom is
  a stock login screen saying "The current theme cannot be loaded". `/opt` is
  world-readable and is where the installer puts it. `install.sh` asks the
  account itself — `sudo -u sddm test -r …` — rather than guessing from the path.
- **A broken theme is not a brick.** SDDM falls back to a working login screen
  and prints the error on it. Seen in the VM, deliberately.
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
