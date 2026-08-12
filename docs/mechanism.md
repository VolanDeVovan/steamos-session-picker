# How SteamOS picks a session, and how the picker gets in front

Everything here was read out of the `steamos-manager` and `sddm` sources and
confirmed against a live Steam Machine (SteamOS holo, sddm 0.21.0-6, kwin 6.4.3)
in August 2026.

## Who decides

Three layers, bottom up.

**1. SDDM config merge** (`sddm.conf(5)`, `src/common/ConfigReader.cpp`):

```
/usr/lib/sddm/sddm.conf.d/*   ->   /etc/sddm.conf.d/*   ->   /etc/sddm.conf
```

Inside a directory files are read alphabetically and the last one wins;
`/etc/sddm.conf` beats everything.

**2. What ships on the device.** `/etc/sddm.conf.d/steamos.conf`:

```ini
[General]
DisplayServer=wayland
InputMethod=qtvirtualkeyboard

[Autologin]
Relogin=true
Session=gamescope-wayland.desktop
User=deck
```

**3. What steamos-manager writes** (`session.rs:313-335`):

| File | Written by | Contents |
|---|---|---|
| `zz-steamos-autologin.conf` | `set-default-login-mode`, `set-default-desktop-session` | `[Autologin]\nSession=…` |
| `zzt-steamos-temp-login.conf` | any `switch-to-*`, one shot | `[Autologin]\nSession=…` |

**The load-bearing fact:** the manager only ever writes the `Session=` key. It
never touches `User=`. Autologin therefore stays alive as long as `User=deck` is
non-empty — which is what lets the picker run **without a password**.

## Making the picker the default session

```sh
steamosctl set-default-desktop-session picker.desktop
steamosctl set-default-login-mode desktop
```

Valve's own code then writes `zz-steamos-autologin.conf` pointing at the picker.
No third-party file lands in `/etc`, so nothing races over file names and
nothing needs re-applying after an atomic update.

Side effect worth having: Steam's own "Switch to Desktop" button now leads to
the picker too, because the picker *is* the default desktop session.

## Pitfalls

- **A session name may not contain `gamescope`.** `is_valid_desktop_session_name()`
  (`session.rs:106-117`) rejects those outright, and
  `set-default-desktop-session` will refuse the name.
- **`Relogin=true` plus a crashing picker is an infinite relogin loop.** Way out
  over ssh: `steamosctl set-default-login-mode game`.
- **`set-default-desktop-session` validates against `XDG_DATA_DIRS` of the same
  user daemon.** Registering the session in `/opt` has to work first, otherwise
  this step silently does nothing.

## Checked on the machine

- **`/etc/sddm.conf` does not exist.** It would outrank every drop-in, so this
  was the one thing that could have invalidated the whole approach. It does not.
- **`/etc/sddm.conf.d/*` is on the default atomic-update keep list**
  (`/usr/lib/rauc/atomic-update-keep.conf`), so the drop-in survives OS updates
  with nothing extra registered. See [install.md](install.md).
- The machine currently offers `plasma.desktop` and `plasmax11.desktop` only,
  and its default login mode is `game`.

## Not verified yet

The whole flow end to end: the picker has never been installed on a Steam
Machine. The first step — registering a session from `/opt` plus
`XDG_DATA_DIRS`, so that `steamosctl get-valid-desktop-sessions` lists it — is
still unrun.
