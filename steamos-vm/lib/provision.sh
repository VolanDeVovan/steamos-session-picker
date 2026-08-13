# provision: make a freshly installed guest reachable, offline.
#
# Everything here happens on the unmounted disk image, which avoids the
# chicken-and-egg of needing a session to enable the thing that gives you a
# session — on a machine whose only display is a VNC socket.

cmd_provision() {
    require_cmd sudo ssh-keygen
    qemu_nbd=$(tool qemu-nbd "$VM_QEMU_NBD")
    btrfs=$(tool btrfs "$VM_BTRFS")
    state_dirs

    [ -f "$DISK" ] || die "nothing installed yet — run: steamos-vm install"
    vm_running && die "the machine is running; stop it first"

    # A key this directory generated for itself, so the VM never borrows the
    # developer's own ssh identity.
    [ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N '' -C 'steamos-vm' -f "$SSH_KEY"

    sudo modprobe nbd max_part=16 2>/dev/null || true
    sudo "$qemu_nbd" --disconnect "$VM_NBD" >/dev/null 2>&1 || true
    sudo "$qemu_nbd" --connect="$VM_NBD" --format=qcow2 "$DISK"
    # shellcheck disable=SC2064
    trap "sudo umount '$MNT' 2>/dev/null; sudo '$qemu_nbd' --disconnect '$VM_NBD' 2>/dev/null" EXIT
    sleep 2

    # SteamOS installs two of everything for atomic updates. The B side is empty
    # on a fresh install and gets written by the first update, which carries
    # these files along with the rest of /etc.
    root=""
    efi=""
    for p in "$VM_NBD"p*; do
        case $(sudo blkid -o value -s PARTLABEL "$p" 2>/dev/null) in
        rootfs-A) root=$p ;;
        efi-A) efi=$p ;;
        esac
    done
    [ -n "$root" ] && [ -n "$efi" ] || die "no SteamOS partitions on $DISK — did the install finish?"

    sudo mount -o rw "$root" "$MNT"
    sudo "$btrfs" property set -ts "$MNT" ro false

    log "installing the guest tree"
    # git records only the executable bit, so modes are applied here rather than
    # taken from the checkout — sshd and sudo both refuse files that are too
    # permissive, and sudo does it silently.
    sudo install -D -m 644 "$SELF_DIR/guest/etc/ssh/sshd_config.d/zz-steamos-vm.conf" \
        "$MNT/etc/ssh/sshd_config.d/zz-steamos-vm.conf"
    sudo install -D -m 440 "$SELF_DIR/guest/etc/sudoers.d/zz-steamos-vm" \
        "$MNT/etc/sudoers.d/zz-steamos-vm"

    # An absolute AuthorizedKeysFile, named in that config: the first boot
    # resizes and repopulates /home, so a key left in the account's own
    # directory does not survive it.
    sudo install -D -m 644 "$SSH_KEY.pub" "$MNT/etc/ssh/steamos-vm_authorized_keys"

    sudo install -d -m 755 "$MNT/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /usr/lib/systemd/system/sshd.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/sshd.service"

    # The kernel, taken out to be booted directly — see start() in lib/vm.sh for
    # why Valve's bootloader is not used. Extracted here because this is the one
    # place that already has the rootfs mounted.
    log "extracting the kernel"
    kernel=$(sudo find "$MNT/boot" -maxdepth 1 -name 'vmlinuz-*' | sort | tail -1)
    initrd=$(sudo find "$MNT/boot" -maxdepth 1 -name 'initramfs-*.img' ! -name '*fallback*' | sort | tail -1)
    [ -n "$kernel" ] && [ -n "$initrd" ] || die "no kernel in the installed rootfs"
    sudo cp "$kernel" "$BOOT/vmlinuz"
    sudo cp "$initrd" "$BOOT/initramfs.img"
    sudo chown "$(id -u):$(id -g)" "$BOOT/vmlinuz" "$BOOT/initramfs.img"
    sudo umount "$MNT"

    sudo blkid -o value -s PARTUUID "$root" >"$BOOT/root-partuuid"
    sudo blkid -o value -s PARTUUID "$efi" >"$BOOT/efi-partuuid"

    trap - EXIT
    sudo "$qemu_nbd" --disconnect "$VM_NBD" >/dev/null
    log "provisioned: sshd enabled, key at $SSH_KEY"
}
