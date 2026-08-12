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

**`/etc/systemd/system/*.mount` is on that default list**, and that is the only
file this project puts in `/etc`. It therefore survives updates with nothing
registered in `/etc/atomic-update.conf.d` — unlike Tailscale, which does need an
entry because `/etc/default/tailscaled` is not covered by the defaults.

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

## Adding a session to a read-only OS without reconfiguring anything

Two things have to find a session before it can be used: SDDM offers it, and
`steamos-manager` validates it for `set-default-desktop-session`. Neither has an
extension point — `/etc/steamos-manager` is empty, and the daemon's
`valid_desktop_sessions()` reads nothing but `XDG_DATA_DIRS`:

```rust
for dir in BaseDirectories::new().data_dirs
    .into_iter()
    .flat_map(|dir| [dir.join("wayland-sessions"), dir.join("xsessions")])
```

Note `data_dirs`, not `data_home`: `~/.local/share/wayland-sessions` is never
looked at. Valve's assumption is that sessions arrive in the OS image, which is
how Bazzite, ChimeraOS and Jovian do it — they build the image. On stock SteamOS
that is not available.

But both consumers already search **`/usr/local/share`**: it is in SDDM's
built-in `SessionDir`, and in the stock `XDG_DATA_DIRS`. It is also on the
read-only rootfs. So the session does not need any configuration changed — it
needs to *appear* in a directory that is already searched:

```ini
# /etc/systemd/system/usr-local-share.mount
[Mount]
What=overlay
Where=/usr/local/share
Type=overlay
Options=lowerdir=/usr/local/share,upperdir=/var/lib/steamos-session-picker/upper,workdir=/var/lib/steamos-session-picker/work
```

This is the same mechanism SteamOS uses for `/etc`, and it composes rather than
replaces: `/usr/local/share/applications` and `/usr/local/share/man` stay
visible, and after an OS update the new rootfs becomes the lower layer, so
nothing is shadowed. `/etc/systemd/system/*.mount` is on the default keep list,
so the unit survives updates too.

**The upper layer cannot live in the checkout.** `/opt` is a bind mount of the
home partition, which SteamOS formats with `casefold` for case-insensitive game
directories, and overlayfs refuses that:

```
overlay: case-insensitive capable filesystem on /opt/... not supported
```

`/var` is a separate ext4 partition without `casefold`, and persists across
updates, so the upper and work directories live there.

### What was tried first, and why it was dropped

Pointing the two consumers at the checkout instead — an SDDM `SessionDir`
drop-in plus `XDG_DATA_DIRS` for the daemon. It works, but it needs two config
overrides rather than none, and the second one is nastier than it looks:
`~/.config/environment.d` is **not** enough, because the session pushes its own
`XDG_DATA_DIRS` into the user manager after it starts and overwrites it. Only a
unit-level `Environment=` survives that. Both were measured on hardware.

## How this installs: the checkout is the installation

```sh
curl -fsSL https://raw.githubusercontent.com/VolanDeVovan/steamos-session-picker/main/bootstrap.sh | sh
```

`bootstrap.sh` clones the repository into `/opt/steamos-session-picker` and hands
over to `install.sh`. Nothing is copied out of the checkout — `install.sh` only
points the system at the directory it is sitting in:

```
/opt/steamos-session-picker/                     the clone; the payload is bin/ and ui/
/var/lib/steamos-session-picker/upper/wayland-sessions/picker.desktop
                                                 the session entry; Exec points into the clone
/var/lib/steamos-session-picker/work/            the overlay's workdir
/etc/systemd/system/usr-local-share.mount        the overlay
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

No configuration file of SDDM's or steamos-manager's is touched at all; see the
section above for why that is possible.

### Why the steps are separate

`install` registers the session and changes no defaults, because SDDM here runs
with `Relogin=true`: a default session that fails to start becomes an endless
relogin loop. So there is `try` — one boot, reverts by itself — before `enable`,
and `disable` exists as the way out, runnable over ssh from another machine if
the screen is stuck.

## Still open

- **`kodi.desktop` does not exist yet.** The machine currently offers only
  `plasma.desktop` and `plasmax11.desktop`. Installing Kodi as its own session
  is separate work; until then that card would fail.
- `/etc/sddm.conf` does **not** exist on this machine — checked, so the SDDM
  drop-ins are authoritative and nothing outranks them.
