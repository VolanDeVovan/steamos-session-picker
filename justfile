# Recipes expect the dev shell on PATH: run `nix develop`, or let direnv load it
# from .envrc.
#
# Nothing here starts a compositor or a greeter. On the machine the picker is
# SDDM's greeter, and only a machine has one of those: layout is checked by
# rendering, the greeter itself by steamos-vm/.

[doc('List recipes')]
default:
  @just --list

[doc('Live window: the picker as an ordinary app, for input and feel')]
run *ARGS:
  qml dev/Preview.qml -- {{ARGS}}

[doc('Render into dev/shots/NAME.png with no display at all')]
shot NAME="picker" *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p dev/shots
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    qml dev/Preview.qml -- --shot="$PWD/dev/shots/{{NAME}}.png" {{ARGS}}
  echo "dev/shots/{{NAME}}.png"

[doc('Re-render the layout review set: every card, plus 4K and 720p')]
shots:
  #!/usr/bin/env bash
  set -euo pipefail
  count=$(grep -c 'file:' dev/sessions.js)
  for i in $(seq 0 $((count - 1))); do
    just shot "card-$i" --select="$i" >/dev/null
  done
  just shot launching --select=0 --launching >/dev/null
  just shot power --power=0 >/dev/null
  just shot 4k --select=1 --size=3840x2160 >/dev/null
  just shot 720p --select=1 --size=1280x720 >/dev/null
  ls dev/shots/

[doc('Everything checkable without hardware: shell syntax, layout, theme')]
check:
  #!/usr/bin/env bash
  set -euo pipefail
  sh -n install.sh
  sh -n bootstrap.sh
  bash -n steamos-vm/steamos-vm
  for f in steamos-vm/lib/*.sh; do bash -n "$f"; done
  # Render to a throwaway path: this proves the scene builds, it is not a
  # picture anyone reviews. Those come from `just shots`.
  tmp=$(mktemp --suffix=.png)
  trap 'rm -f "$tmp"' EXIT
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    qml dev/Preview.qml -- --shot="$tmp"
  test -s "$tmp"
  # The theme cannot be rendered here — it only means anything inside a greeter,
  # where SDDM supplies sessionModel, userModel and sddm.login(). Errors are
  # still worth catching before it reaches one; warnings are not, because every
  # one of those globals is unknown to a linter by definition.
  if qmllint -I "${QML2_IMPORT_PATH:-}" themes/steamos-session-picker/Main.qml 2>&1 | grep '^Error'; then
    echo "themes/steamos-session-picker/Main.qml does not parse" >&2
    exit 1
  fi
  echo "ok — scripts parse, layout renders, the theme is valid QML"
