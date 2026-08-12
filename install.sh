#!/bin/sh
# Register the session picker with SteamOS. Run it on the machine.
#
# The checkout is the installation: nothing is copied anywhere. This script
# points SDDM and steamos-manager at the directory it is sitting in, which is
# why updating is just `git pull` — see `./install.sh update`.
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
SDDM_DROPIN="/etc/sddm.conf.d/00-steamos-session-picker.conf"
ENV_DROPIN="$HOME/.config/environment.d/steamos-session-picker.conf"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'install: %s not found — is this a SteamOS machine?\n' "$1" >&2
        exit 1
    }
}

register() {
    need qml
    need kwin_wayland
    need steamosctl

    # Nothing here touches the read-only rootfs, so `steamos-readonly disable`
    # is never needed, and both locations survive an OS update by themselves:
    #   the checkout      lives under /opt, a bind mount of the home partition
    #   /etc/sddm.conf.d  is already on the default keep list
    # Same shape Tailscale uses on SteamOS. See docs/install.md.

    # Generated rather than committed: the Exec line needs an absolute path,
    # which is only known once the repository has been cloned somewhere.
    mkdir -p "$ROOT/share/wayland-sessions"
    cat >"$ROOT/share/wayland-sessions/$SESSION" <<EOF
[Desktop Entry]
Name=Session picker
Comment=Choose which session to start
Exec=$ROOT/bin/steamos-session-picker
Type=Application
DesktopNames=picker
EOF

    # Two consumers have to find the session: SDDM reads SessionDir to offer it,
    # and steamos-manager validates set-default-desktop-session against its own
    # XDG_DATA_DIRS. Both lists keep the stock directories.
    sudo install -d /etc/sddm.conf.d
    printf '[General]\nSessionDir=%s/share/wayland-sessions,/usr/local/share/wayland-sessions,/usr/share/wayland-sessions\n' \
        "$ROOT" | sudo tee "$SDDM_DROPIN" >/dev/null

    mkdir -p "$(dirname "$ENV_DROPIN")"
    printf 'XDG_DATA_DIRS=%s/share:/usr/local/share:/usr/share\n' "$ROOT" >"$ENV_DROPIN"
}

require_registered() {
    if ! steamosctl get-valid-desktop-sessions 2>/dev/null | grep -q "$SESSION"; then
        printf 'install: %s is not registered yet.\n' "$SESSION" >&2
        printf 'Run `%s install`, then log out and back in so XDG_DATA_DIRS reaches\n' "$0" >&2
        printf 'the steamos-manager user daemon.\n' >&2
        exit 1
    fi
}

case "${1:-install}" in
install)
    register
    printf 'registered from %s\n' "$ROOT"
    printf '\nLog out and back in, then check it is visible:\n'
    printf '  steamosctl get-valid-desktop-sessions\n'
    printf 'Then try it for one boot:  %s try\n' "$0"
    ;;
update)
    need git
    git -C "$ROOT" pull --ff-only
    register
    printf 'updated and re-registered\n'
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
    sudo rm -f "$SDDM_DROPIN"
    rm -f "$ENV_DROPIN"
    rm -rf "$ROOT/share"
    printf 'unregistered. The checkout at %s is still there; remove it if you want it gone.\n' "$ROOT"
    ;;
*)
    printf 'usage: %s {install|update|try|enable|disable|uninstall}\n' "$0" >&2
    exit 2
    ;;
esac
