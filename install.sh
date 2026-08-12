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
# Deliberately split into steps. Registering is harmless and reversible; making
# the picker the default login session is not, because SDDM here runs with
# Relogin=true — a session that fails to start becomes an endless relogin loop.
#
#   ./install.sh install     register the session (changes no defaults)
#   ./install.sh try         start the picker once, reverts on reboot
#   ./install.sh enable      make it the session the machine boots into
#   ./install.sh disable     back to Game Mode — the way out of a relogin loop
#   ./install.sh update      git pull, then re-register
#   ./install.sh uninstall   disable and remove every trace
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

require_registered() {
    if ! steamosctl get-valid-desktop-sessions 2>/dev/null | grep -q "$SESSION"; then
        printf 'install: %s is not registered. Run `%s install` first.\n' "$SESSION" "$0" >&2
        exit 1
    fi
}

case "${1:-install}" in
install)
    register
    printf 'registered from %s\n' "$ROOT"
    printf 'sessions now offered: %s\n' \
        "$(steamosctl get-valid-desktop-sessions | sed -n 's/^- //p' | tr '\n' ' ')"
    printf '\nTry it for one boot:  %s try\n' "$0"
    ;;
update)
    need git
    git -C "$ROOT" pull --ff-only
    # Re-exec rather than carrying on: the pull just rewrote this very file, and
    # a running shell keeps reading its script from the changed offset. Observed
    # doing exactly that — the old register() ran after a new one was pulled in.
    exec "$ROOT/install.sh" install
    ;;
try)
    require_registered
    printf 'starting the picker once; a reboot puts things back\n'
    steamosctl switch-to-desktop-mode "$SESSION"
    ;;
enable)
    require_registered
    steamosctl set-default-desktop-session "$SESSION"
    steamosctl set-default-login-mode desktop
    printf 'the machine now boots into the picker\n'
    printf 'to undo: %s disable\n' "$0"
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
    printf 'unregistered. The checkout at %s is still there; remove it if you want it gone.\n' "$ROOT"
    ;;
*)
    printf 'usage: %s {install|update|try|enable|disable|uninstall}\n' "$0" >&2
    exit 2
    ;;
esac
