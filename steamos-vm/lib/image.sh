# fetch and prepare: getting Valve's recovery image, and making it install
# without a person in front of it.

cmd_fetch() {
    require_cmd curl bunzip2
    state_dirs

    [ -f "$RECOVERY_SRC" ] && {
        log "already have $RECOVERY_SRC"
        return 0
    }

    if [ ! -f "$RECOVERY_BZ2" ]; then
        [ -n "$VM_RECOVERY_URL" ] ||
            die "set VM_RECOVERY_URL to a recovery image (.img.bz2); see steamos-vm.conf"
        log "downloading (about 3 GB)"
        curl -L --fail --progress-bar -o "$RECOVERY_BZ2.part" "$VM_RECOVERY_URL"
        mv "$RECOVERY_BZ2.part" "$RECOVERY_BZ2"
    fi

    log "decompressing (about 8 GB)"
    bunzip2 -c "$RECOVERY_BZ2" >"$RECOVERY_SRC.part"
    mv "$RECOVERY_SRC.part" "$RECOVERY_SRC"
    log "fetched: $RECOVERY_SRC"
}

# Turn the recovery image into an unattended installer.
#
# Valve's own script does the work: repair_device.sh honours NOPROMPT and
# POWEROFF, which is presumably how machines are imaged in the factory. All this
# adds is a systemd unit that runs it at boot — and the guest powering itself
# off is then the signal that the install finished.
#
# A unit, rather than a desktop autostart entry: the recovery image's Plasma
# session does not come up on virtio-gpu without GL, so anything hung off the
# desktop never fires.
#
# It works on a copy, and remakes that copy every time: the recovery system
# writes to its own partitions as it runs, so one that has already installed is
# not a known starting point. Cheap on a filesystem that can reflink, a real
# 8 GB copy otherwise.
cmd_prepare() {
    require_cmd sudo losetup
    btrfs=$(tool btrfs "$VM_BTRFS")
    state_dirs

    [ -f "$RECOVERY_SRC" ] || die "no recovery image yet — run: steamos-vm fetch"
    log "copying the recovery image"
    rm -f "$RECOVERY"
    cp --reflink=auto "$RECOVERY_SRC" "$RECOVERY"

    loop=$(sudo losetup -fP --show "$RECOVERY")
    # shellcheck disable=SC2064
    trap "sudo umount '$MNT' 2>/dev/null; sudo losetup -d '$loop' 2>/dev/null" EXIT

    # The recovery image's layout, which is not the one an installed system has:
    #   p1 vfat esp   p2 vfat efi/grub   p3 btrfs rootfs   p4 ext4 var   p5 ext4 home
    #
    # Mounting the rootfs rw is not enough: the subvolume carries its own
    # read-only flag, and with it set every write fails with EROFS however the
    # filesystem was mounted.
    sudo mount "${loop}p3" "$MNT"
    sudo "$btrfs" property set -ts "$MNT" ro false
    sudo install -D -m 644 "$SELF_DIR/recovery/etc/systemd/system/auto-reimage.service" \
        "$MNT/etc/systemd/system/auto-reimage.service"
    sudo mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf ../auto-reimage.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/auto-reimage.service"
    sudo umount "$MNT"

    # The unit runs a script that lives on a different partition, so say so here,
    # where it can be explained, rather than inside a guest that boots, does
    # nothing and never powers off.
    #
    # Ignore repair_device.sh.orig if you go looking: Valve ships a stray copy
    # full of unresolved conflict markers and a block labelled "NO MERGE -
    # foxnetifier for eng …". It is vestigial; the script beside it is fine.
    sudo mount -o ro "${loop}p5" "$MNT"
    sudo test -x "$MNT/$VM_USER/tools/repair_device.sh" ||
        die "no repair_device.sh in the image — is this a recovery image?"
    sudo umount "$MNT"

    # Put the installer's console on the serial port. Without it the only view
    # is a screenshot of a framebuffer that goes dark the moment anything
    # graphical starts.
    sudo mount "${loop}p2" "$MNT"
    # The kernel line does not begin with `linux`: SteamOS wraps it in its own
    # grub module, as `steamenv_boot<tab>linux /boot/vmlinuz-…`. Match the path
    # instead, and append — the last console= on the line becomes /dev/console,
    # which is where systemd writes.
    grub="$MNT/EFI/steamos/grub.cfg"
    sudo grep -q 'console=ttyS0' "$grub" ||
        sudo sed -i '/linux[[:space:]]\+\/boot\/vmlinuz/ s/$/ console=ttyS0,115200/' "$grub"
    sudo umount "$MNT"

    trap - EXIT
    sudo losetup -d "$loop"
    log "prepared: it will wipe the target disk, install SteamOS, and power off"
}
