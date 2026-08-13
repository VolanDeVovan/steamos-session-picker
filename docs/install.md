# Installing on an immutable SteamOS

Every fact about the filesystem below was read off a running Steam Machine
(SteamOS holo, August 2026). The installation itself was exercised end to end in
[`steamos-vm/`](../steamos-vm/README.md).

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
/etc/systemd/system/*.mount
/etc/group
/etc/gshadow
/etc/passwd
/etc/shadow
...
```

So of the three things this project puts in `/etc`, two are covered by the
defaults and one is not:

| File | Kept by |
|---|---|
| `/etc/sddm.conf.d/zzz-steamos-session-picker.conf` | `/etc/sddm.conf.d/*`, default |
| the `nopasswdlogin` group | `/etc/group`, default |
| `/etc/pam.d/sddm` | **nothing** — hence `/etc/atomic-update.conf.d/steamos-session-picker.conf` |

Discarded files are not lost immediately: a copy goes to `/etc/previous`, and up
to five snapshots are kept in `/var/lib/steamos-atomupd/etc_backup`.

**The one cost of keeping `/etc/pam.d/sddm`** is that our copy then shadows any
future change Valve makes to that file. It is one added line on top of theirs,
`install.sh uninstall` puts the original back from the copy it saved, and
`update` re-derives it — but it is the only file here that is a modification
rather than an addition, and that is worth knowing.

## How other third-party software does it on this machine

**Tailscale** — binaries in `/opt/tailscale`, a unit in `/etc/systemd/system`,
and `/etc/atomic-update.conf.d/tailscale.conf` for the two files the defaults do
not cover. Nothing in `/usr`: `/usr/sbin/tailscaled` does not exist on this
machine, the rootfs was never modified.

**Decky Loader** — everything under `$HOME/homebrew` plus one unit in
`/etc/systemd/system`. Same idea, home partition instead of `/opt` because it is
per-user.

The common shape: **payload on a persistent partition, a couple of small files
in `/etc`, rootfs never touched.** This project is the same shape, and smaller:
no unit at all.

## Adding a login screen to a read-only OS without reconfiguring anything

There is nothing to add to the rootfs. SDDM's theme directory is a **setting**:

```ini
[Theme]
ThemeDir=/opt/steamos-session-picker/themes
Current=steamos-session-picker
```

so the theme is read straight out of the checkout. That is the whole of it.

This replaced a much larger mechanism. When the picker was a *session*, it had
to appear in a directory that both SDDM and `steamos-manager` enumerate, neither
of which has an extension point — `steamos-manager`'s `valid_desktop_sessions()`
reads nothing but `XDG_DATA_DIRS`, and `data_dirs` at that, so
`~/.local/share/wayland-sessions` is never looked at. The way in was an overlay
mount on `/usr/local/share`, a `.mount` unit in `/etc/systemd/system`, a
generated `.desktop` file in `/var/lib`, and two `steamosctl` calls to register
it. **A greeter theme needs none of that**, because a greeter is not a session
and nothing has to validate its name.

**The one thing the path must satisfy** is that user `sddm` can read it. `/opt`
is world-readable; a home directory is mode 700 and the theme silently fails to
load. `install.sh` checks by asking that account, not by looking at the path.

## How this installs: the checkout is the installation

```sh
curl -fsSL https://raw.githubusercontent.com/VolanDeVovan/steamos-session-picker/main/bootstrap.sh | sh
```

`bootstrap.sh` clones the repository into `/opt/steamos-session-picker` and hands
over to `install.sh`. Nothing is copied out of the checkout:

```
/opt/steamos-session-picker/                     the clone; the payload is themes/ and ui/
/etc/sddm.conf.d/zzz-steamos-session-picker.conf autologin off, and where the theme is
/etc/pam.d/sddm                                  one added line
/etc/atomic-update.conf.d/steamos-session-picker.conf
                                                 which keeps that line across an update
group nopasswdlogin                              with one member
~/.config/systemd/user/default.target.wants/cecd.service
                                                 the television remote, see input.md
```

Consequences of that choice, which is why it is made:

- **Updating is `git pull`.** `install.sh update` does exactly that and
  re-applies, and re-running `bootstrap.sh` on an existing checkout updates
  instead of failing.
- **No copy step means no drift** between what is installed and what the
  repository says is installed.
- **The clone is owned by the invoking user**, so pulling needs no privileges.
  `sudo` is used only to create the directory in `/opt` and to write the small
  files in `/etc`.

There is no compiler and no package manager in any of this: SteamOS already
ships `sddm-greeter-qt6` and `kwin_wayland`, which is the entire runtime.

## Why one run is safe

The previous design had to be installed in stages, because a default session
that failed to start became an endless relogin loop. **That failure mode is
gone.** A theme that will not load falls back to a stock login screen with the
error on it; a session that will not start returns to the greeter. Neither is a
loop, so `bootstrap.sh` does the whole thing in one go.

The way out is still there and still runnable over ssh from another computer:

```sh
ssh deck@<machine> /opt/steamos-session-picker/install.sh disable
```

## Still open

- **`kodi.desktop` does not exist yet.** The machine currently offers only
  `plasma.desktop`, `plasmax11.desktop` and Game Mode. Installing Kodi as its
  own session is separate work.
- The install has been run end to end in the VM only. Nothing here has been on a
  Steam Machine yet.
