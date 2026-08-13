# steamos-vm

Valve's SteamOS in a local virtual machine, installed unattended and resettable
in a second. It exists so that display managers, session entries, PAM, greeter
themes and the boot path can be tested without a Steam Machine, a Steam Deck or
a television in the room.

**Game Mode does not run in here** — see [the limitation](#the-limitation-game-mode)
below. A freshly installed SteamOS boots into it, so `view` shows "Display output
is not active", which reads like a broken VM and is not one. For something to
look at and click, send it to the desktop:

```sh
./steamos-vm ssh 'steamosctl switch-to-desktop-mode plasma.desktop'
```

That prints a D-Bus "TransactionIsDestructive" error and switches anyway: it is
stopping the session it is being run from. Plasma comes up on virtio-gpu, and
everything else this exists for — SDDM, session entries, PAM, the boot path —
works either way.

This directory is self-contained — it reads nothing outside itself and writes
nothing outside `var/` — so copying it into another repository is enough to use
it there.

## Using it

Once:

```sh
VM_RECOVERY_URL=https://…/steamdeck-recovery-N.img.bz2 ./steamos-vm fetch
./steamos-vm prepare      # make Valve's image install without a person present
./steamos-vm install      # ~3 minutes; the guest powers itself off when done
./steamos-vm provision    # sshd and a key, planted with the machine off
./steamos-vm snapshot     # keep that state as the one reset returns to
```

Then, as often as you like:

```sh
./steamos-vm start                 # boots, waits for ssh
./steamos-vm view                  # its screen in a window, mouse and keyboard included
./steamos-vm ssh                   # a shell, or: ssh 'systemctl status sddm'
./steamos-vm push ../my-project    # copy a working tree in
./steamos-vm screenshot shot.png   # what is on the screen right now
./steamos-vm key right right ret   # type at it, on its own keyboard
./steamos-vm reset                 # discard everything since the snapshot
./steamos-vm stop
```

`key` and `screenshot` are the pair that makes a login screen testable at all:
nobody is sitting here, and a greeter answers to nothing but input. The keys go
in through QEMU's emulated keyboard, so they travel the same evdev and libinput
path a real one takes rather than being injected somewhere convenient.

`reset` is a file that holds only the difference from the golden image, so
throwing away a broken experiment costs nothing and no test inherits the last
one's mess.

To install again, run `prepare` again first: it remakes the copy, and the
recovery system writes to its own partitions as it runs, so one that has already
installed is not a known starting point.

## Requirements

`./steamos-vm doctor` checks all of these and prints what it resolved.

| Needed | For |
|---|---|
| `qemu-system-x86_64`, `qemu-img`, `qemu-nbd` | the machine, its disks, and reaching them while it is off |
| OVMF firmware | SteamOS lays down an ESP and will not come up under SeaBIOS |
| `btrfs-progs` | the SteamOS rootfs is btrfs, and its subvolume is read-only |
| `curl`, `bzip2` | fetching the recovery image |
| `openssh`, `python3` | talking to the guest, and to QEMU's monitor |
| `sudo`, write access to `/dev/kvm`, the `nbd` module | mounting images, and not being unusably slow |
| ~30 GB free | 3 GB compressed image, 8 GB decompressed, a copy of it, and the disks |

Plain Linux, and nothing here knows about any particular distribution: tools are
taken from `PATH` and the firmware is looked for where distributions put it.

Where a machine keeps them somewhere else — NixOS keeps everything in its
store — name them once in `steamos-vm.local.conf`, which is git-ignored because
it describes the host rather than the project:

```sh
: "${VM_OVMF_CODE:=/nix/store/…-OVMF-…/FV/OVMF_CODE.fd}"
: "${VM_OVMF_VARS:=/nix/store/…-OVMF-…/FV/OVMF_VARS.fd}"
: "${VM_BTRFS:=/nix/store/…-btrfs-progs-…/bin/btrfs}"
: "${VM_VIEWER:=/nix/store/…-tigervnc-…/bin/vncviewer}"
```

After that `./steamos-vm` runs from any shell. This repository's `nix develop`
provides the same things, but the tool does not need it.

## Configuration

`steamos-vm.conf` holds the defaults with each one documented in place. Override
them per machine in `steamos-vm.local.conf`, which is git-ignored, or per run
from the environment:

```sh
VM_RAM=16G VM_SSH_PORT=2299 ./steamos-vm start
```

The environment wins over the local file, which wins over the defaults. Point
`VM_STATE_DIR` somewhere else to keep the images off this filesystem.

## Layout

| Path | What it is |
|---|---|
| `steamos-vm` | the only executable: usage and dispatch, no logic |
| `steamos-vm.conf` | committed defaults, every setting documented where it is set |
| `lib/` | one file per concern: `common` (paths, tool lookup), `image` (fetch, prepare), `provision`, `vm` (QEMU and the running machine), `monitor.py` |
| `guest/` | files planted in the **installed** system, under the paths they take there |
| `recovery/` | files planted in **Valve's recovery image** — a different target, so a different tree |
| `var/` | everything generated: images, firmware variables, the ssh key, pid, sockets, logs. Git-ignored |

Guest-side configuration is kept as real files rather than heredocs so it can be
read and linted as what it is — `visudo -cf guest/etc/sudoers.d/zz-steamos-vm`
checks the file in the checkout. Modes are applied on install, because git
records only the executable bit and both sshd and sudo refuse files that are too
permissive, sudo silently.

## Watching it

Nobody is sitting in front of this screen, so there are two channels instead of
one, and both turned out to be necessary:

```sh
./steamos-vm screenshot frame.png   # the display, once something graphical starts
tail -f var/run/serial.log          # the kernel, for a boot that fails before that
```

A third one exists for input devices that are not the keyboard — a television
remote, a controller plugged in after boot. Both reach a compositor as uinput
devices created by root, and one of those can be conjured with about forty lines
of Python against the stdlib; the guest has no `python-evdev` and needs none.
That is how "does the login screen see a device that appeared after it did" was
answered without a television.

## The limitation: Game Mode

Game Mode does not work in a virtual machine, here or anywhere. Igalia, who
develop SteamOS, say so in their own QEMU instructions — *"the Gaming mode …
requires additional development to make it work with QEMU and will not work with
these instructions"* — and every published guide says the same and tells you to
use the desktop session instead.

It is worth knowing exactly where it stops, because "needs an AMD GPU" is the
usual explanation and it is wrong. Two layers are in the way:

1. **Vulkan.** gamescope opens a Vulkan instance before it does anything else,
   and wants a device that supports DRM format modifiers. A plain virtio-vga has
   no Vulkan at all; a software driver in the guest has Vulkan without modifiers,
   which gamescope refuses. QEMU's Vulkan passthrough does provide one.
2. **Scanout.** virtio-gpu offers exactly one format on its primary plane,
   XRGB8888, and tells userspace it supports no format modifiers. gamescope
   composites in ARGB8888, so every frame is refused — `Cannot import FB to DRM:
   format 0x34325241` — and no framebuffer ever reaches the CRTC.

Both were taken apart and the second was fixed, in a patched guest `virtio_gpu`
that offers ARGB8888 and a linear modifier list; after it gamescope negotiates
cleanly and starts with no errors at all. What remained was the passthrough
itself failing to back gamescope's buffers — `vkr: failed to import resource` on
the host — which is QEMU and virglrenderer, not SteamOS. That work is in the
history at `87479bf` if it is ever worth resuming; a host with an AMD or Intel
GPU, where the passthrough proxies to Mesa rather than to a proprietary driver,
is the obvious next thing to try.

None of it is needed here. What this VM is for — installing, session entries,
SDDM, PAM, greeters, the boot path — does not involve Game Mode, and timings
measured under software rendering would not mean anything anyway. Game Mode
belongs on the machine.

## What had to be discovered

Each of these cost a boot cycle, so they are written down rather than
rediscovered.

**Unattended needs no patching at all.** `repair_device.sh` already honours
`NOPROMPT=1` and `POWEROFF=1`, which is presumably how machines are imaged in
the factory. A systemd unit runs it, and *the guest powering itself off is the
signal that the install finished* — no log scraping, no polling for a string.

The unit is what runs it, not a desktop autostart entry: the recovery image's
Plasma session never comes up on virtio-gpu without GL, so anything hung off the
desktop never fires.

**`repair_device.sh.orig` is a red herring.** The image ships a second copy of
that script, left over from Valve's build, full of unresolved git conflict
markers and a block labelled *"NO MERGE - foxnetifier for eng w/fremont poc3
stuff in it"*. It cost an afternoon. The script systemd runs is the one beside
it, and it is fine.

**The firmware only boots NVMe.** USB and virtio-blk both leave OVMF on its
splash for ever. The recovery image is attached as a second NVMe device and the
empty target stays first, so it answers to `/dev/nvme0n1` — the disk
`repair_device.sh` hardcodes. Use plain OVMF; the xen build never hands off.

**The recovery image must be writable.** Attached `readonly=on`, the guest
throws `critical medium error` at its own home partition and the install dies.

**The rootfs is btrfs with a read-only subvolume.** Not ext4, so `tune2fs` is
the wrong tool, and mounting `rw` is not enough on its own:
`btrfs property set -ts <mnt> ro false`.

**Valve's bootloader never starts under QEMU.** The firmware loads
`steamcl.efi` — which ships beside a file called `steamcl-restricted` — and the
guest sits on the TianoCore splash. Nothing here needs it, so the kernel is
booted directly, extracted from the installed rootfs by `provision`. That also
puts the command line under our control, which is how the console reaches the
serial log.

**Two kernel arguments are not optional.** `root=PARTUUID=…` and
`steamos.efi=PARTUUID=…`: the initramfs hook builds `/dev/disk/by-partsets/*`
from the second, and without it the boot stops in an emergency shell with
`ERROR: EFI partition not found`. Valve's chainloader normally supplies it. The
name is `steamos.efi`, with a dot — `steamos_efi` is the hook's internal
variable and is silently ignored.

**A "99-" sudoers file loses.** `/etc/sudoers.d` is applied in lexical order and
the last match wins, so `99-` is overridden by SteamOS's own `wheel` file —
digits sort before letters — and the password prompt comes back. `zz-` works.

**The ssh key goes in `/etc/ssh`, not in a home directory.** First boot resizes
and repopulates `/home`, taking an `authorized_keys` there with it. An absolute
`AuthorizedKeysFile` survives.

**Kill QEMU by pid, never by name.** How the process presents itself depends on
packaging — under a nixpkgs wrapper it appears as `.qemu-system-x8`, with a
leading dot — so `pkill qemu-system-x86_64` matches nothing, the old machine
keeps running, and the next start fails with *"Is another process using the
image?"*, which names neither the cause nor the machine still holding it.
