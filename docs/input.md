# Input: what the picker actually receives

The picker handles **keys and pointer**, nothing else. That is not a shortcut —
it is what the target hardware sends.

## On the Steam Machine

**Controller.** The puck hands the system real USB-HID devices, four slots of
them (`if02`–`if05` in `/proc/bus/input/devices`):

```
N: Name="Valve Software Steam Controller Puck Keyboard"   H: Handlers=sysrq kbd event4
N: Name="Valve Software Steam Controller Puck Mouse"      H: Handlers=event3 mouse0
```

This is lizard mode, implemented in the dongle itself. While Steam is not
running — and in a login picker it is by definition not running — the controller
is arrow keys, Enter and Esc, plus a mouse driven from the trackpad. No SDL, no
gamepad API, no compositor plugin.

**TV remote.** Fremont exposes `/dev/cec0` through `cros-ec-cec`, and Valve's
own `cecd -e` turns CEC into a uinput device emitting ordinary key codes. So the
remote arrives as a keyboard as well.

`cecd.service` is a **user** unit. It runs inside the `deck` session, which the
picker is — so the remote works there for free. It would not work in an SDDM
greeter, which runs as user `sddm`.

**Keyboard and mouse.** Plain USB, nothing special.

## On the Steam Deck

The `hid-steam` kernel driver does the same job: D-pad to arrows, A to Enter,
B to Esc. Known caveat, recorded on that host: any SDL application that opens
hidraw knocks the pad out of lizard mode.

## Steam takes the controller away — verified 2026-08-12

Plugging the puck (`28de:1304`) into a desktop Linux box produced the expected
eight nodes, four `Puck Keyboard` and four `Puck Mouse`. They were **not**
grabbed by anyone, yet a 60-second capture across all of them recorded zero
events.

The reason showed up as a ninth device: `28de:11ff` "Microsoft X-Box 360 pad 0",
purely virtual (`/devices/virtual/input/input36`, handlers `js0 event22`).
**Steam Input** creates it. Steam talks to the controller over hidraw, takes it
out of lizard mode, and re-publishes it as a virtual X360 pad; the HID keyboard
nodes stay present but silent.

Quitting Steam brings lizard mode straight back — with Steam stopped, the
controller navigates the picker with no bridge, no driver and no gamepad code.
**Confirmed by driving the running picker with the controller.**

This is why the picker needs nothing for controller support: its session never
has Steam alive underneath it, which is exactly the state in which the puck
behaves as a keyboard and mouse.

A bridge that converts joystick events into keys (evdev to uinput) was written
and then deleted: it answered a problem that does not exist on this hardware. If
a pad that has no lizard mode ever needs supporting, write it then — and against
the stdlib, since stock SteamOS has no python-evdev.
