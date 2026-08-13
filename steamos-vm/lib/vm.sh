# Everything about a machine: its QEMU invocation, and the commands that run,
# copy into, photograph, snapshot and reset it.

# Two things about this hardware matter and neither is obvious:
#
#   * the target disk must be NVMe. The recovery image's installer looks for
#     /dev/nvme0n1 and reports "no valid storage target" for a SATA or IDE disk.
#   * it must boot UEFI. SteamOS lays down an ESP and will not come up under
#     SeaBIOS.
qemu_args() {
    find_ovmf
    QEMU_ARGS=(
        -machine q35,accel=kvm
        -cpu host
        -smp "$VM_CPUS"
        -m "$VM_RAM"
        -drive "if=pflash,format=raw,readonly=on,file=$VM_OVMF_CODE"
        -drive "if=pflash,format=raw,file=$OVMF_VARS"
        -drive "if=none,id=target,format=qcow2,file=$DISK"
        -device nvme,drive=target,serial=steamos
        # 127.0.0.1, not every interface: QEMU's VNC has no password, and the
        # guest's screen is not something to publish to the network.
        -device virtio-vga -display none -vnc "127.0.0.1$VM_VNC"
        # A monitor socket, so this machine can look at its own screen without a
        # person: `screenshot` writes the current frame to a file through it.
        -monitor "unix:$MONITOR,server,nowait"
        # The guest's console in a file. The framebuffer goes dark as soon as
        # anything graphical starts, so this is the only durable view of a boot.
        -serial "file:$SERIAL"
        -netdev "user,id=net0,hostfwd=tcp::$VM_SSH_PORT-:22"
        -device virtio-net-pci,netdev=net0
        -device qemu-xhci -device usb-tablet -device usb-kbd
    )
}

# Start QEMU detached and record its pid, so callers do not have to background
# it themselves and `stop` has something exact to kill.
qemu_start() {
    require_cmd qemu-system-x86_64
    vm_kill
    qemu-system-x86_64 "${QEMU_ARGS[@]}" "$@" >"$RUN/qemu.log" 2>&1 &
    echo $! >"$PIDFILE"
    sleep 2
    vm_running || {
        sed 's/^/  /' "$RUN/qemu.log" >&2
        die "QEMU exited immediately"
    }
}

cmd_install() {
    require_cmd qemu-img
    state_dirs
    [ -f "$RECOVERY" ] || die "no prepared image — run: steamos-vm fetch && steamos-vm prepare"

    rm -f "$DISK" "$OVMF_VARS"
    qemu-img create -f qcow2 "$DISK" "$VM_DISK_SIZE" >/dev/null

    qemu_args
    # The recovery image rides on a second NVMe device. It cannot be USB or
    # virtio-blk — this firmware boots neither and sits on its splash for ever —
    # and it must not be the first NVMe either, because repair_device.sh
    # hardcodes /dev/nvme0n1 and that has to be the disk being installed to.
    #
    # Not read-only: the recovery system writes to its own home partition, and
    # attached readonly the guest throws "critical medium error" and dies.
    qemu_start \
        -drive "if=none,id=rec,format=raw,file=$RECOVERY" \
        -device nvme,drive=rec,serial=recovery,bootindex=0

    log "installing; the guest powers itself off when it is done (about 3 minutes)"
    waited=0
    while [ "$waited" -lt 1800 ]; do
        vm_running || break
        sleep 10
        waited=$((waited + 10))
    done
    vm_running && die "still running after 30 minutes; look at $SERIAL"

    # The guest stopping is the signal, but it is also what happens if someone
    # stops it by hand or QEMU dies — so make sure something was written. About
    # 10 GB is, and an untouched qcow2 is under a megabyte.
    [ "$(du -m "$DISK" | cut -f1)" -gt 1024 ] ||
        die "the guest stopped but $DISK is still empty; look at $SERIAL"

    log "installed: $DISK"
    log "next: steamos-vm provision"
}

cmd_start() {
    state_dirs
    [ -f "$DISK" ] || die "nothing installed yet — run: steamos-vm install"

    # Boot the kernel directly rather than through Valve's chainloader.
    # steamcl.efi ships beside a file called "steamcl-restricted" and never
    # hands off under QEMU: the firmware starts it and the guest sits on the
    # TianoCore splash with nothing written anywhere. Nothing here needs Valve's
    # bootloader; it needs SteamOS userspace. Doing it by hand also puts the
    # kernel command line under our control, which is how the console reaches
    # the serial log.
    [ -f "$BOOT/vmlinuz" ] ||
        die "no extracted kernel in $BOOT — run: steamos-vm provision"

    qemu_args
    # steamos.efi is not optional: the initramfs hook builds
    # /dev/disk/by-partsets/* from that partition, and without it the boot stops
    # in an emergency shell with "ERROR: EFI partition not found". Valve's
    # chainloader is what normally supplies it. The name has a dot in it;
    # steamos_efi is the hook's internal variable and is silently ignored.
    qemu_start \
        -kernel "$BOOT/vmlinuz" \
        -initrd "$BOOT/initramfs.img" \
        -append "root=PARTUUID=$(cat "$BOOT/root-partuuid") rw steamos.efi=PARTUUID=$(cat "$BOOT/efi-partuuid") console=tty0 console=ttyS0,115200"

    log "started; vnc $VM_VNC, ssh on port $VM_SSH_PORT"
    if wait_for_ssh 180; then
        log "ssh is up"
    else
        log "no ssh yet — it may still be booting; look at $SERIAL"
    fi
}

# Look at the machine, and use it. QEMU is started with a tablet and a keyboard
# attached, so a viewer gives a working mouse and typing, not just a picture.
cmd_view() {
    vm_running || die "the machine is not running — run: steamos-vm start"
    viewer=$VM_VIEWER
    for v in vncviewer gvncviewer remmina vinagre wlvncc; do
        [ -n "$viewer" ] && break
        viewer=$(command -v "$v" || true)
    done
    port=$((5900 + ${VM_VNC#:}))
    [ -n "$viewer" ] || die "no VNC viewer installed — point one at 127.0.0.1:$port"
    log "$viewer -> 127.0.0.1:$port"
    exec "$viewer" "127.0.0.1:$port"
}

cmd_stop() {
    vm_kill
    log "stopped"
}

cmd_ssh() {
    [ -f "$SSH_KEY" ] || die "no key yet — run: steamos-vm provision"
    vm_ssh "$@"
}

# Copy a directory into the guest. The default destination is the account's home
# and never /tmp: a checkout under /tmp survives until the next boot and then
# does not, which for anything installed as a session shows up as a relogin loop
# with no explanation.
cmd_push() {
    src=${1:-} && [ -n "$src" ] || die "usage: steamos-vm push <dir> [dest]"
    [ -d "$src" ] || die "$src is not a directory"
    dest=${2:-/home/$VM_USER/$(basename "$(cd "$src" && pwd)")}
    case "$dest" in
    /tmp/* | /var/tmp/* | /dev/shm/*)
        die "$dest is emptied at boot; pick somewhere permanent"
        ;;
    esac

    vm_ssh "rm -rf '$dest' && mkdir -p '$dest'"
    # From a git checkout, send exactly what git would show you: tracked files
    # plus untracked ones that are not ignored. Otherwise pushing a repository
    # that contains this directory would send var/ along with it — the golden
    # image included, which is eleven gigabytes of the guest's own disk.
    if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$src" ls-files -co --exclude-standard -z |
            tar -C "$src" --null -T - -czf -
    else
        tar -C "$src" --exclude=.git -czf - .
    fi | vm_ssh "tar xzf - -C '$dest'"
    log "pushed to $dest"
}

cmd_screenshot() {
    require_cmd python3
    vm_running || die "the machine is not running"
    # QEMU writes the file itself, from its own working directory, so the path
    # handed to it has to be absolute.
    out=$(realpath -m "${1:-$STATE/screenshot.png}")
    python3 "$SELF_DIR/lib/monitor.py" "$MONITOR" "screendump $out -f png" >/dev/null
    log "$out"
}

# Type at the guest, from a script. Nobody is sitting in front of this screen,
# so a login screen or any other thing that only answers to a keyboard cannot be
# tested through ssh — the keys have to arrive as keys, on the emulated
# keyboard, through the same evdev and libinput path a real one takes.
#
#   steamos-vm key right right ret
#
# Names are QEMU's own (`ret`, `esc`, `kp_enter`, `a`, `1`, …), and a run of
# them is sent in order with a pause between, because whatever is on screen is
# usually animating.
cmd_key() {
    require_cmd python3
    vm_running || die "the machine is not running"
    [ $# -gt 0 ] || die "usage: steamos-vm key <name>... — e.g. key right ret"
    for k in "$@"; do
        python3 "$SELF_DIR/lib/monitor.py" "$MONITOR" "sendkey $k" >/dev/null
        sleep "$VM_KEY_DELAY"
    done
    log "sent: $*"
}

# Keep the installed-and-provisioned disk as the state every test starts from.
# What runs afterwards is a thin overlay on it, so throwing an experiment away
# costs a file that holds only the difference.
cmd_snapshot() {
    require_cmd qemu-img
    [ -f "$DISK" ] || die "nothing to snapshot"
    vm_running && die "the machine is running; stop it first"
    mv "$DISK" "$GOLDEN"
    qemu-img create -f qcow2 -b "$GOLDEN" -F qcow2 "$DISK" >/dev/null
    log "golden image: $GOLDEN"
}

cmd_reset() {
    require_cmd qemu-img
    [ -f "$GOLDEN" ] || die "no golden image — run: steamos-vm snapshot"
    vm_kill
    rm -f "$DISK"
    qemu-img create -f qcow2 -b "$GOLDEN" -F qcow2 "$DISK" >/dev/null
    log "reset to the golden image"
}

# Where a new host actually fails is the firmware, the kernel module and the
# free space — none of which announce themselves until something else breaks.
cmd_doctor() {
    state_dirs
    printf 'qemu           %s\n' "$(command -v qemu-system-x86_64 || echo MISSING)"
    printf 'qemu-img       %s\n' "$(command -v qemu-img || echo MISSING)"
    printf 'qemu-nbd       %s\n' "${VM_QEMU_NBD:-$(command -v qemu-nbd || echo MISSING)}"
    printf 'btrfs          %s\n' "${VM_BTRFS:-$(command -v btrfs || echo MISSING)}"
    (find_ovmf && printf 'firmware       %s\n' "$VM_OVMF_CODE") || true
    printf 'kvm            %s\n' "$([ -w /dev/kvm ] && echo "writable" || echo "no access to /dev/kvm — the VM will be unusably slow")"
    printf 'nbd module     %s\n' "$(lsmod 2>/dev/null | grep -q '^nbd' && echo loaded || echo "not loaded (provision loads it)")"
    printf 'state dir      %s (%s free)\n' "$STATE" "$(df -h "$STATE" | awk 'NR==2 {print $4}')"
    printf 'machine        %s\n' "$(vm_running && echo "running, ssh on port $VM_SSH_PORT" || echo "stopped")"
}
