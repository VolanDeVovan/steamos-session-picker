# Installing on an immutable SteamOS

Every fact below was read off a running Steam Machine (SteamOS holo, August
2026), not inferred from documentation.

## What the filesystem actually looks like

```
/          /dev/nvme0n1p4  btrfs   read-only in normal operation, A/B swapped by updates
/etc       overlay         lowerdir=/new_root/etc, upperdir=/var/lib/overlays/etc/upper
/var       /dev/nvme0n1p6  ext4    persistent
/home      /dev/nvme0n1p8  ext4    persistent
/opt       /dev/nvme0n1p8[/.steamos/offload/opt]   ext4, persistent
/srv,/root,/nix, parts of /var — the same offload trick
```

The important one: **`/opt` is not part of the image at all.** It is a bind
mount out of the home partition, so anything installed there is untouched by an
OS update and needs no `steamos-readonly disable`. Same for `/srv`, `/root` and,
amusingly, `/nix` — SteamOS pre-creates those offload directories.

`/etc` is different: it is an overlay whose upper layer is wiped selectively on
every update.

## The atomic-update keep list

Since SteamOS 3.6 an update keeps only files on an allowlist and discards the
rest of the `/etc` overlay. Defaults live in
`/usr/lib/rauc/atomic-update-keep.conf`; third parties add their own file to
`/etc/atomic-update.conf.d/*.conf`, one path per line, `*` matching within a
path segment and `**` across segments.

What the default list already covers, verbatim from the machine:

```
/etc/atomic-update.conf.d/*.conf
/etc/sddm.conf.d/*
/etc/systemd/system/*.service
/etc/systemd/system/*.service.d/**
/etc/systemd/system/*.socket
/etc/systemd/system/*.mount
/etc/NetworkManager/system-connections/*
/etc/ssh/*_key
...
```

Discarded files are not lost immediately: a copy goes to `/etc/previous`, and up
to five snapshots are kept in `/var/lib/steamos-atomupd/etc_backup`.

**`/etc/sddm.conf.d/*` is on that default list.** Everything this project puts
in `/etc` therefore survives updates without registering anything. An earlier
version of these notes claimed the opposite and made the installer print a
warning about re-applying the drop-in after updates; that was wrong, and the
warning is gone.

## How other third-party software does it on this machine

**Tailscale** — installed, and the pattern is exactly the one above:

| Piece | Where |
|---|---|
| Binaries | `/opt/tailscale/tailscale`, `/opt/tailscale/tailscaled` (33 and 43 MB, static) |
| Unit | `/etc/systemd/system/tailscaled.service` — default keep list covers it |
| Config | `/etc/default/tailscaled` |
| Keep list | `/etc/atomic-update.conf.d/tailscale.conf`, two lines, for the two files above that the defaults do not cover |

Note what is *not* there: nothing in `/usr`. `/usr/sbin/tailscaled` does not
exist on this machine — the rootfs was never modified.

**Decky Loader** — everything under `$HOME/homebrew` (`plugins`, `services`,
`settings`, `data`, `logs`) plus `/etc/systemd/system/plugin_loader.service`.
Same idea, home partition instead of `/opt` because it is per-user.

**The Determinate Systems Nix installer** is the example the SteamOS developers
themselves point at for the keep-list mechanism.

The common shape: **payload on a persistent partition, a couple of small files
in `/etc`, rootfs never touched.**

## How this installs: the checkout is the installation

```sh
curl -fsSL https://raw.githubusercontent.com/VolanDeVovan/steamos-session-picker/main/bootstrap.sh | sh
```

`bootstrap.sh` clones the repository into `/opt/steamos-session-picker` and hands
over to `install.sh`. Nothing is copied out of the checkout — `install.sh` only
points the system at the directory it is sitting in:

```
/opt/steamos-session-picker/                        the clone; the payload is bin/ and ui/
/opt/steamos-session-picker/share/wayland-sessions/picker.desktop
                                                  generated, gitignored, Exec is absolute
/etc/sddm.conf.d/00-steamos-session-picker.conf     SessionDir, includes the above
~/.config/environment.d/steamos-session-picker.conf XDG_DATA_DIRS, includes the above
```

Consequences of that choice, which is why it is made:

- **Updating is `git pull`.** `install.sh update` does exactly that and
  re-registers, and re-running `bootstrap.sh` on an existing checkout updates
  instead of failing.
- **No copy step means no drift** between what is installed and what the
  repository says is installed.
- **The clone is owned by the invoking user**, so pulling needs no privileges.
  The session runs as that same user, so nothing crosses a privilege boundary;
  `sudo` is used only to create the directory in `/opt` and to write the one
  file in `/etc`.

There is no compiler and no package manager in any of this: SteamOS already
ships `qml` (qt6-declarative) and `kwin_wayland`, which is the entire runtime.

Two drop-ins rather than one because two different things have to find the
session: SDDM reads `SessionDir` to offer it, while `steamos-manager` validates
the name passed to `set-default-desktop-session` against its own
`XDG_DATA_DIRS`.

### Why the steps are separate

`install` registers the session and changes no defaults, because SDDM here runs
with `Relogin=true`: a default session that fails to start becomes an endless
relogin loop. So there is `try` — one boot, reverts by itself — before `enable`,
and `disable` exists as the way out, runnable over ssh from another machine if
the screen is stuck.

## Still open

- **Whether `~/.config/environment.d` actually reaches the steamos-manager user
  daemon.** This is the one unproven link in the chain; if the session does not
  appear in `steamosctl get-valid-desktop-sessions` after a re-login, the
  fallbacks are `systemctl --user set-environment`, a unit drop-in for
  `steamos-manager.service`, or a bind mount into
  `/usr/local/share/wayland-sessions` via a unit in `/etc/systemd/system`
  (which the default keep list preserves).
- **`kodi.desktop` does not exist yet.** The machine currently offers only
  `plasma.desktop` and `plasmax11.desktop`. Installing Kodi as its own session
  is separate work; until then that card would fail.
- `/etc/sddm.conf` does **not** exist on this machine — checked, so the SDDM
  drop-ins are authoritative and nothing outranks them.
