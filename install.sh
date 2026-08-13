#!/bin/sh
# Register the session picker with SteamOS. Run it on the machine.
#
# The checkout is the installation: nothing is copied anywhere. Only two things
# land outside it, and neither overrides any configuration — see docs/install.md
# for why that is possible at all:
#
#   /var/lib/steamos-session-picker/  the session entry, and the overlay's workdir
#   /etc/systemd/system/usr-local-share.mount
#
# A bare run does everything, which is safe because the entry point returns the
# machine to Game Mode if the picker fails to start three times in a boot. The
# steps stay separately available for when something is being changed.
#
#   ./install.sh              install it and boot into it — the whole thing
#   ./install.sh try          start the picker once, reverts on reboot
#   ./install.sh enable       make it the session the machine boots into
#   ./install.sh disable      back to Game Mode — the way out of a relogin loop
#   ./install.sh update       git pull, then re-apply
#   ./install.sh uninstall    disable and remove every trace
#   --no-enable               with no command: set up, but keep booting as before
#
# If the machine ever boots into a loop, from another computer:
#   ssh deck@<machine> steamosctl set-default-login-mode game
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SESSION="picker.desktop" # must not contain "gamescope": steamos-manager rejects those
STATE="/var/lib/steamos-session-picker"
MOUNT_UNIT="/etc/systemd/system/usr-local-share.mount"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'install: %s not found — is this a SteamOS machine?\n' "$1" >&2
        exit 1
    }
}

register() {
    # Not `need qml`: on SteamOS that finds qt5-declarative's binary, which
    # cannot load this UI at all. bin/qml-runtime picks the Qt 6 one.
    qml_bin=$("$ROOT/bin/qml-runtime") || exit 1
    printf 'qml runtime: %s\n' "$qml_bin"
    need kwin_wayland
    need steamosctl

    # Both SDDM and steamos-manager already search /usr/local/share: it is in
    # SDDM's built-in SessionDir and in the stock XDG_DATA_DIRS. It is also on
    # the read-only rootfs. So rather than reconfiguring either of them, the
    # session entry is added to that directory with an overlay — the same
    # mechanism SteamOS itself uses for /etc.
    #
    # The upper layer has to live on /var, not in the checkout: the home
    # partition is mounted with casefold, and overlayfs refuses a
    # case-insensitive-capable filesystem as an upper layer.
    sudo install -d "$STATE/upper/wayland-sessions" "$STATE/work"

    sudo tee "$STATE/upper/wayland-sessions/$SESSION" >/dev/null <<EOF
[Desktop Entry]
Name=Session picker
Comment=Choose which session to start
Exec=$ROOT/bin/steamos-session-picker
Type=Application
DesktopNames=picker
EOF

    # /etc/systemd/system/*.mount is on the atomic-update keep list, so this
    # survives OS updates untouched.
    sudo tee "$MOUNT_UNIT" >/dev/null <<EOF
[Unit]
Description=Overlay /usr/local/share, adding a session without touching the read-only rootfs
Documentation=https://github.com/VolanDeVovan/steamos-session-picker
ConditionPathIsDirectory=$STATE/upper/wayland-sessions
Before=sddm.service

[Mount]
What=overlay
Where=/usr/local/share
Type=overlay
Options=lowerdir=/usr/local/share,upperdir=$STATE/upper,workdir=$STATE/work

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl reenable usr-local-share.mount >/dev/null
    sudo systemctl restart usr-local-share.mount

    # steamos-manager caches nothing, but it read the old directory list at
    # start, so give it the mounted one.
    systemctl --user restart steamos-manager.service
}

enable_boot() {
    require_registered
    steamosctl set-default-desktop-session "$SESSION"
    steamosctl set-default-login-mode desktop
    printf 'the machine now boots into the picker\n'
    printf 'to undo: %s disable\n' "$0"
}

usage() {
    cat >&2 <<EOF
usage: $0 [command] [--no-enable]

  (no command)  set the picker up and make it the session the machine boots into
  try           start the picker once, now; the next boot is unaffected
  enable        make the picker the session the machine boots into
  disable       go back to booting straight into Game Mode
  update        git pull, then re-apply
  uninstall     disable, then remove every trace outside this checkout

  --no-enable   set up only; do not change what the machine boots into
EOF
}

require_registered() {
    if ! steamosctl get-valid-desktop-sessions 2>/dev/null | grep -q "$SESSION"; then
        printf 'install: %s is not set up. Run `%s` first.\n' "$SESSION" "$0" >&2
        exit 1
    fi
}

command=""
no_enable=""
for arg in "$@"; do
    case "$arg" in
    --no-enable) no_enable=1 ;;
    -*)
        usage
        exit 2
        ;;
    *) command=$arg ;;
    esac
done

case "${command:-install}" in
install)
    register
    printf 'set up from %s\n' "$ROOT"
    if [ -n "$no_enable" ]; then
        printf 'the machine still boots into Game Mode; to change that: %s enable\n' "$0"
    else
        enable_boot
    fi
    ;;
update)
    need git
    git -C "$ROOT" pull --ff-only
    # Re-exec rather than carrying on: the pull just rewrote this very file, and
    # a running shell keeps reading its script from the changed offset. Observed
    # doing exactly that — the old register() ran after a new one was pulled in.
    # --no-enable because updating must not change how the machine boots.
    exec "$ROOT/install.sh" --no-enable
    ;;
try)
    require_registered
    printf 'starting the picker once; a reboot puts things back\n'
    steamosctl switch-to-desktop-mode "$SESSION"
    ;;
enable)
    enable_boot
    ;;
disable)
    steamosctl set-default-login-mode game
    printf 'back to booting straight into Game Mode\n'
    ;;
uninstall)
    steamosctl set-default-login-mode game || true
    sudo systemctl disable --now usr-local-share.mount || true
    sudo rm -f "$MOUNT_UNIT"
    sudo systemctl daemon-reload
    sudo rm -rf "$STATE"
    systemctl --user restart steamos-manager.service || true
    printf 'removed. The checkout at %s is still there; delete it if you want it gone.\n' "$ROOT"
    ;;
*)
    usage
    exit 2
    ;;
esac
