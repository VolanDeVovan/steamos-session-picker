# Shared by every subcommand: configuration, paths, and the few helpers that
# more than one of them needs. Sourced, never executed.

log() { printf '%s\n' "$*"; }
die() {
    printf 'steamos-vm: %s\n' "$*" >&2
    exit 1
}

# Load configuration and derive every path from it.
#
# The local file is read first so that its `: "${NAME:=…}"` assignments win over
# the defaults, and the environment wins over both because it is set before
# either runs.
load_config() {
    [ -f "$SELF_DIR/steamos-vm.local.conf" ] && . "$SELF_DIR/steamos-vm.local.conf"
    . "$SELF_DIR/steamos-vm.conf"

    STATE=$VM_STATE_DIR
    RUN="$STATE/run"
    MNT="$STATE/mnt"
    DISK="$STATE/disk.qcow2"
    GOLDEN="$STATE/golden.qcow2"
    RECOVERY_BZ2="$STATE/recovery.img.bz2"
    RECOVERY_SRC="$STATE/recovery.img"
    RECOVERY="$STATE/recovery-auto.img"
    OVMF_VARS="$STATE/OVMF_VARS.fd"
    BOOT="$STATE/boot"
    SSH_KEY="$STATE/ssh/id_ed25519"
    PIDFILE="$RUN/vm.pid"
    MONITOR="$RUN/monitor.sock"
    SERIAL="$RUN/serial.log"

    # The guest is reached through a port forward on loopback, and its host key
    # changes with every reinstall, so checking it could only ever produce a
    # false alarm. 127.0.0.1 rather than localhost: on a dual-stack host that
    # name may resolve to ::1 first, which the forward does not answer.
    SSH_OPTS=(
        -i "$SSH_KEY"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -p "$VM_SSH_PORT"
    )
    SSH_TARGET="$VM_USER@127.0.0.1"
}

state_dirs() { mkdir -p "$RUN" "$MNT" "$BOOT" "$STATE/ssh"; }

require_cmd() {
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 ||
            die "$c is not installed — see Requirements in README.md"
    done
}

# Resolve a command to an absolute path, because it is about to be handed to
# sudo, whose secure_path is a short fixed list that need not contain wherever
# this one lives.
tool() {
    path=${2:-$(command -v "$1" || true)}
    [ -n "$path" ] || die "$1 is not installed — see Requirements in README.md"
    printf '%s' "$path"
}

# The firmware. Distributions disagree about where OVMF lives, so try the paths
# they use; set VM_OVMF_CODE and VM_OVMF_VARS to skip the search entirely, which
# is what you want if it is not installed system-wide.
#
# Never the xen build: it never handed off to the image's own bootloader and the
# guest sat spinning in firmware.
find_ovmf() {
    if [ -z "$VM_OVMF_CODE" ]; then
        for dir in /usr/share/OVMF /usr/share/edk2/ovmf /usr/share/edk2-ovmf/x64 \
            /usr/share/qemu /usr/share/ovmf/x64; do
            for name in OVMF_CODE_4M.fd OVMF_CODE.fd edk2-x86_64-code.fd; do
                [ -f "$dir/$name" ] && {
                    VM_OVMF_CODE="$dir/$name"
                    VM_OVMF_VARS=${VM_OVMF_VARS:-$dir/$(printf '%s' "$name" | sed 's/CODE/VARS/;s/code/vars/')}
                    break 2
                }
            done
        done
    fi
    [ -n "$VM_OVMF_CODE" ] ||
        die "no OVMF firmware found — install it, or set VM_OVMF_CODE and VM_OVMF_VARS"
    [ -f "${VM_OVMF_VARS:-}" ] ||
        die "no OVMF variable template beside $VM_OVMF_CODE — set VM_OVMF_VARS"

    # The variable store is written to and is per-machine, so it is a copy.
    [ -f "$OVMF_VARS" ] || cp "$VM_OVMF_VARS" "$OVMF_VARS"
    chmod u+w "$OVMF_VARS"
}

vm_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# Kill by pid, never by name: how the process presents itself depends on
# packaging — under a nixpkgs wrapper it appears as ".qemu-system-x8", with a
# leading dot — so a pattern match can silently hit nothing, leaving the old
# machine holding the disk lock.
vm_kill() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        # `|| true` because the pid file outlives the machine: after a guest
        # powers itself off the file is still there and the kill fails, which
        # under `set -e` would end the run without a word.
        kill -9 "$pid" 2>/dev/null || true
        # Wait for it to actually be gone. The forwarded ssh port stays bound
        # until the process is reaped, so starting the next machine immediately
        # fails with "Could not set up host forwarding rule" — which reads like
        # a configuration problem and is not one.
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    fi
    rm -f "$PIDFILE" "$MONITOR"
    return 0
}

vm_ssh() { ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"; }

wait_for_ssh() {
    waited=0
    while [ "$waited" -lt "${1:-180}" ]; do
        timeout 8 ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "$SSH_TARGET" true 2>/dev/null && return 0
        sleep 5
        waited=$((waited + 5))
    done
    return 1
}
