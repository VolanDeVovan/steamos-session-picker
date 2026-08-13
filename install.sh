#!/bin/sh
# Make the session picker SDDM's login screen. Run it on the machine.
#
# The checkout is the installation: nothing is copied anywhere. What lands
# outside it is small, and none of it replaces a file SteamOS ships:
#
#   /etc/sddm.conf.d/zzz-steamos-session-picker.conf   turns autologin off and
#                                                      names this theme
#   /etc/pam.d/sddm                                    one added line, so the
#                                                      nopasswdlogin group may
#                                                      log in without a password
#   /etc/atomic-update.conf.d/steamos-session-picker.conf
#                                                      keeps that line across an
#                                                      OS update
#   ~sddm/.config/…                                    two services SteamOS
#                                                      already ships, hung off
#                                                      the greeter's own
#                                                      session: cecd for the
#                                                      television remote, and
#                                                      powerdevil so the screen
#                                                      goes off and the machine
#                                                      sleeps at the picker
#
# plus the `nopasswdlogin` group itself, with one member. Why each of those is
# the shape it is: docs/mechanism.md.
#
#   ./install.sh              set it up and boot into it — the whole thing
#   ./install.sh try          restart SDDM now, to see it without rebooting
#   ./install.sh disable      back to booting straight into Game Mode
#   ./install.sh update       git pull, then re-apply
#   ./install.sh uninstall    disable and remove every trace
#   --no-enable               with no command: set up, but keep booting as before
#
# If the screen ever ends up somewhere useless, from another computer:
#   ssh deck@<machine> /opt/steamos-session-picker/install.sh disable
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

THEME="steamos-session-picker"
THEME_DIR="$ROOT/themes"
SDDM_CONF="/etc/sddm.conf.d/zzz-steamos-session-picker.conf"
PAM_FILE="/etc/pam.d/sddm"
KEEP_FILE="/etc/atomic-update.conf.d/steamos-session-picker.conf"
GROUP="nopasswdlogin"

# The one line added to SDDM's PAM stack, and the marker that finds it again.
PAM_MARK="# steamos-session-picker"
PAM_RULE="auth        sufficient  pam_succeed_if.so user ingroup $GROUP $PAM_MARK"

# How long the picker may sit on a television before the screen goes off, and
# before the machine sleeps. Five minutes and fifteen: the same two-step a
# console does, so walking away from the login screen ends where walking away
# from Game Mode ends. powerdevil will not go below 30 seconds whatever it is
# asked for, and PICKER_SLEEP=0 leaves the machine awake.
blank=${PICKER_BLANK:-300}
sleep_after=${PICKER_SLEEP:-900}

# Checked here rather than where they are used: both are read halfway through
# the install, and `set -e` on a non-number would stop it after PAM and the
# group had already been written — the half-set-up state the sudo prompt above
# exists to avoid.
for n in "$blank" "$sleep_after"; do
    case $n in
    '' | *[!0-9]*)
        printf 'install: PICKER_BLANK and PICKER_SLEEP are seconds, and "%s" is not.\n' "$n" >&2
        exit 2
        ;;
    esac
done

# Run it as yourself, and it calls sudo where it needs to; `sudo ./install.sh`
# works too. Either way this is the account being set up, and it is never root:
# the whole job is to arrange for one person to reach their sessions, and root
# is not that person on any machine this is meant for.
user=${PICKER_USER:-${SUDO_USER:-$(id -un)}}

if [ "$user" = root ]; then
    printf 'install: this sets a machine up for one account, and root is not it.\n' >&2
    printf 'install: run it as that account — it calls sudo where it needs to —\n' >&2
    printf 'install: or name the account: PICKER_USER=deck sudo %s\n' "$0" >&2
    # Reached from a root shell or `sudo -i`, where SUDO_USER is not set and
    # there is nothing to infer from. Silently setting root up instead would
    # produce a login screen that cannot log anyone in.
    exit 1
fi

# Root can do everything except *be* that account. `update` runs git, and git
# must not be root even when the rest is: objects it wrote would be root-owned,
# and the next ordinary `git pull` would fail on them.
as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$user" "$@"
    else
        "$@"
    fi
}

# The greeter's own account. Its home is where systemd looks for that account's
# user units, and two services below are hung off it.
sddm_home() {
    getent passwd sddm | cut -d: -f6
}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'install: %s not found — is this a SteamOS machine?\n' "$1" >&2
        exit 1
    }
}

# SDDM's configuration, PAM and the group all belong to root, so about eight
# steps here need sudo. Ask for it once, before anything has been touched:
# otherwise a password typed wrongly at the fifth step leaves the machine
# half-set-up, which is the one state nothing here knows how to describe.
#
# `sudo -v` is silent where sudo needs no password, prompts once where it does,
# and refuses immediately where the account may not use it at all.
require_sudo() {
    [ "$(id -u)" -eq 0 ] && return 0
    need sudo

    if sudo -n true 2>/dev/null; then
        return 0
    fi

    if [ ! -t 0 ] && [ ! -c /dev/tty ]; then
        printf 'install: sudo wants a password and there is no terminal to ask on.\n' >&2
        printf 'install: run it from a shell, or as: sudo %s\n' "$0" >&2
        exit 1
    fi

    printf 'install: this changes SDDM'"'"'s configuration and PAM, so it needs sudo.\n'
    printf 'install: your password is asked once, now, before anything is changed.\n'
    sudo -v || {
        printf '\ninstall: without sudo nothing can be installed. Nothing was changed.\n' >&2
        # A fresh SteamOS has no password on this account at all, and sudo
        # cannot be given one it does not have. It is the likeliest reason to
        # land here, and it is not obvious.
        if [ "$(passwd -S "$user" 2>/dev/null | awk '{print $2}')" = "NP" ]; then
            printf 'install: %s has no password set — `passwd` first, then try again.\n' "$user" >&2
        fi
        exit 1
    }
}

check() {
    need sddm
    need kwin_wayland

    # The greeter binary is chosen from QtVersion= in the theme's metadata, and
    # only the Qt 6 one can load this theme: SteamOS ships both, and Qt 5
    # rejects versionless imports with "Library import requires a version".
    [ -x /usr/bin/sddm-greeter-qt6 ] || {
        printf 'install: /usr/bin/sddm-greeter-qt6 is missing; this theme needs the Qt 6 greeter\n' >&2
        exit 1
    }

    # The one failure with no way back from a sofa. The picker has no password
    # field — it never asks for one — so a machine whose PAM stack cannot say
    # yes to the group shows every card and starts none of them, and the way in
    # is ssh or a text console. Everything else here fails visibly and
    # recoverably; this would not, so the module is looked for before the
    # machine is changed rather than found missing at the next boot.
    [ -e /usr/lib/security/pam_succeed_if.so ] || {
        printf 'install: /usr/lib/security/pam_succeed_if.so is missing.\n' >&2
        printf 'install: the passwordless login is that module, and the picker cannot\n' >&2
        printf 'install: ask for a password instead. Nothing was changed.\n' >&2
        exit 1
    }

    # The session entry used to be what had to survive the next boot; now it is
    # the theme. From /tmp it does not: the greeter falls back to a stock theme
    # and says so on screen, which is not what anyone installed this for.
    case "$ROOT" in
    /tmp/* | /var/tmp/* | /dev/shm/*)
        printf 'install: %s is on a directory that is emptied at boot.\n' "$ROOT" >&2
        printf 'install: clone somewhere permanent — /opt is what the installer uses.\n' >&2
        exit 1
        ;;
    esac

    # The greeter runs as user sddm, not as you. A checkout in a home directory
    # is mode 700 and unreadable to it, and the only symptom is a stock login
    # screen with "The current theme cannot be loaded" on it. Ask the account
    # itself rather than guessing from the path — and only if it exists, so a
    # machine without it fails with its own name rather than with this message.
    getent passwd sddm >/dev/null || {
        printf 'install: there is no sddm account; is SDDM installed?\n' >&2
        exit 1
    }
    if ! sudo -u sddm test -r "$THEME_DIR/$THEME/Main.qml"; then
        printf 'install: user sddm cannot read %s\n' "$THEME_DIR/$THEME/Main.qml" >&2
        printf 'install: the greeter runs as that account. Clone somewhere it can read —\n' >&2
        printf 'install: /opt is what the installer uses; a home directory is mode 700.\n' >&2
        exit 1
    fi
}

# Passwordless, and genuinely so: PAM is asked and answers yes, because the
# account is in a group that SDDM's stack — and nothing else's — accepts without
# a password. sudo and ssh are untouched. This is the same mechanism Debian and
# Ubuntu ship for their own display managers.
allow_passwordless() {
    getent group "$GROUP" >/dev/null || sudo groupadd "$GROUP"
    id -nG "$user" | tr ' ' '\n' | grep -qx "$GROUP" || sudo gpasswd -a "$user" "$GROUP" >/dev/null

    if ! grep -qF "$PAM_MARK" "$PAM_FILE"; then
        # The first rule in the stack, so it is reached before pam_unix asks for
        # anything — but after the `#%PAM-1.0` line, which by convention opens
        # the file. A `sufficient` that does not match simply falls through to
        # the stack SteamOS ships, which is what should happen for everyone else.
        sudo cp "$PAM_FILE" "$PAM_FILE.steamos-session-picker.orig"
        awk -v rule="$PAM_RULE" '
            NR == 1 && /^#%PAM/ { print; print ""; print rule; inserted = 1; next }
            NR == 1 && !inserted { print rule; inserted = 1 }
            { print }
        ' "$PAM_FILE" | sudo tee "$PAM_FILE.new" >/dev/null
        sudo mv "$PAM_FILE.new" "$PAM_FILE"
    fi

    # /etc/pam.d is not on SteamOS's default atomic-update keep list, so without
    # this the line is dropped by the next OS update and the machine asks for a
    # password it was never given. /etc/group is on the default list already.
    sudo install -d /etc/atomic-update.conf.d
    sudo tee "$KEEP_FILE" >/dev/null <<EOF
# Keep the one line install.sh adds to SDDM's PAM stack across an OS update.
# Without it the picker comes up and cannot start anything.
$PAM_FILE
EOF
}

# The television remote. cecd turns CEC into a uinput keyboard, and Valve runs
# it as a *user* unit wanted by graphical-session.target — so it exists inside a
# session and nowhere else, which is exactly wrong for a login screen.
#
# The temptation is to drag it out of sessions, with a system unit or with
# linger. Both fail, and the second one fails twice: cecd wants a session bus
# for com.steampowered.CecDaemon1 and exits without one, and the two devices it
# needs — /dev/cec0 and /dev/uinput — are handed out by udev's `uaccess` tag,
# which is an ACL following whoever holds the seat. A daemon deliberately
# outside every session is refused by both, "EACCES: Permission denied",
# active and publishing nothing.
#
# Whoever holds the seat while the picker is up is the greeter, as user sddm.
# So the daemon does not want to be dragged anywhere: it wants an instance in
# the greeter's own session, where the ACL already points. Then each session has
# one — Valve's in the user's, this one in the greeter's — and neither needs a
# permission that was not already granted.
#
# Verified on a Steam Machine: `cecd cros-ec-cec` appears as an ordinary
# keyboard, on a machine with no user session at all.
keep_remote_alive() {
    [ -f /usr/lib/systemd/user/cecd.service ] || return 0

    # sddm's home, not ~/.config: this unit belongs to the greeter's account.
    wants=$(sddm_home)/.config/systemd/user/default.target.wants
    sudo install -d -o sddm -g sddm -m 755 "$wants"
    sudo ln -sf /usr/lib/systemd/user/cecd.service "$wants/cecd.service"
    sudo chown -h sddm:sddm "$wants/cecd.service"
    printf 'the remote now works while the picker is on screen\n'
}

# The screen, once the room has walked away. Game Mode leaves idling to Steam
# and Desktop Mode to powerdevil, which is part of the Plasma session — so the
# login screen was the one place on this machine with no opinion at all, and a
# picker left alone lit a static picture on a television until someone came
# back. On an OLED that is not a question of watts.
#
# powerdevil is in the image and is an ordinary D-Bus service, so it goes where
# cecd went: an instance in the greeter's own session. Two things it is handed
# inside Plasma and has to be given here:
#
#   WAYLAND_DISPLAY   Plasma exports its session environment into the user
#                     manager and the greeter does not. Without it powerdevil
#                     takes the xcb plugin, finds no display, and aborts.
#   no burst limit    default.target is reached before kwin has made the
#                     socket, so the first tries fail on purpose. Retrying is
#                     the whole answer, and the default five-in-ten-seconds
#                     gives up before the compositor is there.
#
# The profile is the two steps a console makes: screen off, then sleep. Valve's
# own /etc/xdg/powerdevilrc turns auto-suspend off on AC and sets it for a Deck
# on battery, which is a handheld's answer and not a living room's — a machine
# left at a login screen should end up where it ends up when it is left in Game
# Mode. Everything not named here is still inherited from that file.
#
# **Waking from that sleep has not been tested on a Steam Machine.** Game Mode
# sleeps and wakes from the pad, and the wake sources are the kernel's rather
# than Steam's, so it should hold here too — but "should" is the word. The
# power button is the way back if it does not, and `PICKER_SLEEP=0` is the way
# to say the machine may not sleep at the picker at all.
blank_the_screen() {
    [ -f /usr/lib/systemd/user/plasma-powerdevil.service ] || return 0

    home=$(sddm_home)
    wants=$home/.config/systemd/user/default.target.wants
    drop=$home/.config/systemd/user/plasma-powerdevil.service.d

    sudo install -d -o sddm -g sddm -m 755 "$wants" "$drop"
    sudo ln -sf /usr/lib/systemd/user/plasma-powerdevil.service "$wants/plasma-powerdevil.service"
    sudo chown -h sddm:sddm "$wants/plasma-powerdevil.service"

    sudo tee "$drop/greeter.conf" >/dev/null <<EOF
# Written by $ROOT/install.sh — powerdevil in a session that is not Plasma's.

[Unit]
StartLimitIntervalSec=0

[Service]
Environment=WAYLAND_DISPLAY=wayland-0
# Wait for the compositor instead of dying on it. default.target is reached
# before kwin has made the socket, and a service that aborts and is restarted
# gets there in the end — but only by way of a crash the journal cannot tell
# from a real one. Waiting says what is meant, and a machine where no wayland
# greeter ever appears — the silent X11 fallback in development.md — gives up
# after a minute and retries slowly instead of respawning twice a second.
ExecStartPre=/bin/sh -c 'n=0; while [ ! -S "\$XDG_RUNTIME_DIR/wayland-0" ]; do [ \$n -ge 120 ] && exit 1; n=\$((n + 1)); sleep 0.5; done'
# always, not on-failure: losing the compositor is how this ends every time a
# session starts, and whether that arrives as a crash or as a clean exit is
# powerdevil's business, not something to depend on.
Restart=always
RestartSec=5
EOF

    # AutoSuspendAction is the same enumeration as the power button's, where 1
    # is sleep and 0 is do nothing — Valve's file uses both values, which is
    # where they are read from rather than guessed.
    sudo tee "$home/.config/powerdevilrc" >/dev/null <<EOF
# Written by $ROOT/install.sh. This is the greeter's account, so it says
# nothing about the sessions it starts — they carry their own.
#
# On mains only. A Steam Deck running from its battery keeps the numbers Valve
# ships in /etc/xdg/powerdevilrc — screen off at 60s, asleep at 300s — which is
# a better answer for a handheld than anything decided here.
[AC][Display]
TurnOffDisplayIdleTimeoutSec=$blank

[AC][SuspendAndShutdown]
AutoSuspendAction=$([ "$sleep_after" -gt 0 ] && echo 1 || echo 0)
AutoSuspendIdleTimeoutSec=$sleep_after
EOF
    sudo chown sddm:sddm "$drop/greeter.conf" "$home/.config/powerdevilrc"
    if [ "$sleep_after" -gt 0 ]; then
        printf 'on mains, the picker turns the screen off after %ss and sleeps after %ss\n' "$blank" "$sleep_after"
    else
        printf 'on mains, the picker turns the screen off after %ss and never sleeps\n' "$blank"
    fi
}

enable_boot() {
    # Everything in one drop-in, sorted after both files steamos-manager writes
    # (zz-steamos-autologin.conf and zzt-steamos-temp-login.conf), so it is the
    # last word on autologin without any of them being edited. SDDM merges by
    # key, not by file.
    sudo install -d /etc/sddm.conf.d
    sudo tee "$SDDM_CONF" >/dev/null <<EOF
# Written by $ROOT/install.sh — remove it, or run install.sh disable, to go back
# to booting straight into Game Mode.

[Autologin]
# The whole point. With no user there is no autologin, so SDDM shows the greeter
# — which is the picker. Session= is deliberately left alone: steamos-manager
# writes it, and with autologin off it is only a default, not a decision.
User=

[General]
DisplayServer=wayland
# The greeter loads a virtual keyboard for typing passwords. This one never asks
# for a password, and not loading it is time the room does not spend waiting.
InputMethod=

[Wayland]
# SteamOS does not ship weston, which is what SDDM's default names. Left alone,
# the wayland greeter fails to start and SDDM silently falls back to X11.
CompositorCommand=kwin_wayland --no-lockscreen --no-global-shortcuts --locale1

[Theme]
ThemeDir=$THEME_DIR
Current=$THEME
EOF
    printf 'the machine now boots into the picker\n'
    printf 'to see it now: %s try     to undo: %s disable\n' "$0" "$0"
}

usage() {
    cat >&2 <<EOF
usage: $0 [command] [--no-enable]

  (no command)  set the picker up and make it the login screen
  enable        make it the login screen, having set up with --no-enable
  try           restart SDDM now, to see it without rebooting
  disable       go back to booting straight into Game Mode
  update        git pull, then re-apply
  uninstall     disable, then remove every trace outside this checkout

  --no-enable   set up only; do not change what the machine boots into
EOF
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
    require_sudo
    check
    allow_passwordless
    keep_remote_alive
    blank_the_screen
    printf 'set up from %s, for user %s\n' "$ROOT" "$user"
    if [ -n "$no_enable" ]; then
        # `update` comes through here, on a machine that is usually already
        # booting into the picker — so say what is true rather than assuming
        # this is a first run.
        if [ -f "$SDDM_CONF" ]; then
            printf 'the machine still boots into the picker\n'
        else
            printf 'the machine still boots into Game Mode; to change that: %s enable\n' "$0"
        fi
    else
        enable_boot
    fi
    ;;
enable)
    require_sudo
    check
    enable_boot
    ;;
update)
    need git
    as_user git -C "$ROOT" pull --ff-only
    # Re-exec rather than carrying on: the pull just rewrote this very file, and
    # a running shell keeps reading its script from the changed offset. Observed
    # doing exactly that. --no-enable because updating must not change how the
    # machine boots.
    exec "$ROOT/install.sh" --no-enable
    ;;
try)
    [ -f "$SDDM_CONF" ] || {
        printf 'install: not set up yet — run `%s` first.\n' "$0" >&2
        exit 1
    }
    require_sudo
    printf 'restarting SDDM; anything running in the current session will stop\n'
    # --no-block, because restarting SDDM tears down the session this script may
    # be running inside, and a blocking call would be killed halfway through it.
    sudo systemctl --no-block restart sddm
    ;;
disable)
    require_sudo
    sudo rm -f "$SDDM_CONF"
    printf 'back to booting the way SteamOS does; it takes effect at the next boot\n'
    printf 'or immediately with: sudo systemctl restart sddm\n'
    # Deliberately kept, so `enable` is one file again. With autologin back on
    # there is no greeter to log in at, which makes the rule inert rather than
    # merely unused — but it is a permission, so say that it is still there.
    printf 'the nopasswdlogin rule is left in place; %s uninstall removes it\n' "$0"
    ;;
uninstall)
    require_sudo
    sudo rm -f "$SDDM_CONF" "$KEEP_FILE"
    sudo rm -f "$(sddm_home)/.config/systemd/user/default.target.wants/cecd.service"
    sudo rm -f "$(sddm_home)/.config/systemd/user/default.target.wants/plasma-powerdevil.service"
    sudo rm -rf "$(sddm_home)/.config/systemd/user/plasma-powerdevil.service.d"
    sudo rm -f "$(sddm_home)/.config/powerdevilrc"
    if [ -f "$PAM_FILE.steamos-session-picker.orig" ]; then
        sudo mv "$PAM_FILE.steamos-session-picker.orig" "$PAM_FILE"
    else
        sudo sed -i "/$PAM_MARK\$/d" "$PAM_FILE"
    fi
    # The group goes only if we are the last thing using it: it is a stock
    # Debian/Ubuntu name and something else may have put someone in it.
    sudo gpasswd -d "$user" "$GROUP" >/dev/null 2>&1 || true
    if getent group "$GROUP" | cut -d: -f4 | grep -q '^$'; then
        sudo groupdel "$GROUP" 2>/dev/null || true
    fi
    printf 'removed. The checkout at %s is still there; delete it if you want it gone.\n' "$ROOT"
    ;;
*)
    usage
    exit 2
    ;;
esac
