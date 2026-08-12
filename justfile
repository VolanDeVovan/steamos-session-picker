# Recipes expect the dev shell on PATH: run `nix develop`, or let direnv load it
# from .envrc.
#
# Nothing here starts a compositor locally: the picker's session is only ever
# run on the target. Layout is checked by rendering, the rest on the machine.

[doc('List recipes')]
default:
  @just --list

[doc('Live window: the picker as an ordinary app, for input and feel')]
run *ARGS:
  qml ui/Picker.qml -- {{ARGS}}

[doc('Render into dev/shots/NAME.png with no display at all')]
shot NAME="picker" *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p dev/shots
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    qml ui/Picker.qml -- --shot="$PWD/dev/shots/{{NAME}}.png" {{ARGS}}
  echo "dev/shots/{{NAME}}.png"

[doc('Re-render the layout review set: every card, plus 4K and 720p')]
shots:
  #!/usr/bin/env bash
  set -euo pipefail
  count=$(grep -c 'target:' ui/sessions.js)
  for i in $(seq 0 $((count - 1))); do
    just shot "card-$i" --select="$i" >/dev/null
  done
  just shot launching --select=0 --launching >/dev/null
  just shot 4k --select=1 --size=3840x2160 >/dev/null
  just shot 720p --select=1 --size=1280x720 >/dev/null
  ls dev/shots/

[doc('Everything checkable without hardware: shell syntax and the layout')]
check:
  #!/usr/bin/env bash
  set -euo pipefail
  sh -n bin/steamos-session-picker
  sh -n bin/compositor-session
  sh -n install.sh
  sh -n bootstrap.sh
  # Render to a throwaway path: this proves the scene builds, it is not a
  # picture anyone reviews. Those come from `just shots`.
  tmp=$(mktemp --suffix=.png)
  trap 'rm -f "$tmp"' EXIT
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    qml ui/Picker.qml -- --shot="$tmp"
  test -s "$tmp"
  echo "ok — scripts parse, layout renders"
