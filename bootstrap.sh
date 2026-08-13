#!/bin/sh
# One-liner entry point, meant to be piped from the raw file on GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/bootstrap.sh | sh
#
# It clones the repository into /opt — a bind mount of the home partition, so it
# survives SteamOS updates — and hands over to install.sh. Running it again
# updates an existing checkout instead of failing.
#
# One run does the whole thing: clone, allow the account to log in without a
# password, and make the picker SDDM's login screen. That is safe to do in one
# go because nothing here can trap the machine: a greeter that fails to load
# falls back to a stock one, and a session that fails to start returns to the
# greeter — neither is a loop.
#
# To undo:  /opt/steamos-session-picker/install.sh disable
# To set up without changing what boots:  PICKER_ARGS=--no-enable
set -eu

REPO="${PICKER_REPO:-https://github.com/VolanDeVovan/steamos-session-picker.git}"
BRANCH="${PICKER_BRANCH:-main}"
DEST="${PICKER_DEST:-/opt/steamos-session-picker}"

for tool in git sudo; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'bootstrap: %s is required\n' "$tool" >&2
        exit 1
    }
done

command -v steamosctl >/dev/null 2>&1 ||
    printf 'bootstrap: warning — steamosctl not found, this may not be SteamOS\n' >&2

if [ -d "$DEST/.git" ]; then
    printf 'bootstrap: updating %s\n' "$DEST"
    git -C "$DEST" pull --ff-only
else
    printf 'bootstrap: cloning into %s\n' "$DEST"
    # Owned by the invoking user so later `git pull` needs no privileges. The
    # session runs as that same user, so this crosses no privilege boundary.
    sudo install -d -o "$(id -un)" -g "$(id -gn)" "$DEST"
    git clone --branch "$BRANCH" "$REPO" "$DEST"
fi

exec "$DEST/install.sh" ${PICKER_ARGS:-}
