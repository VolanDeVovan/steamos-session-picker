# Input: what the picker actually receives

The picker handles **keys and pointer**, nothing else. That is not a shortcut —
it is what the target hardware sends.

Since the picker became SDDM's greeter there is one new question behind all of
it: the greeter runs as user `sddm`, in a logind session of class `greeter`, not
as `deck`. Every device below has to reach *that*.

## On the Steam Machine

**Controller.** The puck hands the system real USB-HID devices, four slots of
them (`if02`–`if05` in `/proc/bus/input/devices`):

```
N: Name="Valve Software Steam Controller Puck Keyboard"   H: Handlers=sysrq kbd event4
N: Name="Valve Software Steam Controller Puck Mouse"      H: Handlers=event3 mouse0
```

This is lizard mode, implemented in the dongle itself. While Steam is not
running — and at a login screen it is by definition not running — the controller
is arrow keys, Enter and Esc, plus a mouse driven from the trackpad. No SDL, no
gamepad API, no compositor plugin.

**TV remote.** Fremont exposes `/dev/cec0` through `cros-ec-cec`, and Valve's
own `cecd -e` turns CEC into a **uinput device emitting ordinary key codes**. So
the remote arrives as a keyboard as well.

**Keyboard and mouse.** Plain USB, nothing special.

### What that leaves to design with

Arrows, Enter and Esc. That is the whole vocabulary a room actually has, from
the pad and from the remote alike, and it is why Sleep and Restart sit in a row
below the shelf reached with **Down** rather than on a button of their own: an
X or a Y exists only on the keyboard nobody has in front of a television.
Esc — B on the pad — comes back up, because on a controller that button means
"back" before it means anything else.

### The puck against the greeter, without a puck

Being two HID devices is exactly what makes the controller reproducible without
one. A uinput keyboard and a uinput mouse, published together under the puck's
own names and IDs (`28de:1304`) by root, *after* the greeter was already on
screen — which is also what a controller plugged in after boot looks like:

| What was sent | What the picker did |
|---|---|
| two `KEY_RIGHT` on the keyboard device | selection moved two cards, no cursor |
| relative motion onto the first card | selection followed the pointer to it |

Both in `steamos-vm/`. The second is the interesting one: it is the trackpad
half, and it proves the "whichever input was used last wins" rule holds in the
greeter and not only in a window.

What this does **not** prove is a real puck on a real Steam Machine at this
greeter — the radio, lizard mode and udev's view of a genuine USB device are all
outside a VM. It proves that the greeter treats such devices exactly as the old
picker session did, which was the only thing the move to a greeter put at risk.

A pad with **no** lizard mode is a different matter and would not work: it is a
joystick, not a keyboard, and this picker reads keys. Nothing on a Steam Machine
or a Deck is in that category.

## On the Steam Deck

The `hid-steam` kernel driver does the same job: D-pad to arrows, A to Enter,
B to Esc. Known caveat, recorded on that host: any SDL application that opens
hidraw knocks the pad out of lizard mode.

## The remote, and the one thing the greeter changed

`cecd.service` is a **user** unit, `WantedBy=graphical-session.target`. It runs
inside the `deck` session — so when the picker *was* a session it worked for
free, and when the picker became the greeter it stopped existing at exactly the
moment it was wanted.

Three things had to be established, and all three now are.

**It cannot simply become a system service.** Tried first, on the machine: cecd
wants a session bus for `com.steampowered.CecDaemon1` and exits with an I/O
error without one.

**It does not want to be dragged out of a session at all.** The obvious move —
keep the daemon alive past the session that started it, with linger and a want
on `default.target` — works in the sense that the process survives, and then
fails on the machine for a reason a VM cannot show, because a VM has no
`/dev/cec0` to be refused:

```
WARN cecd: Unable to get initial device list: EACCES: Permission denied
WARN cecd::device: Failed to open uinput device: Permission denied (os error 13)
```

Both devices it needs are handed out by udev's `uaccess` tag — including
`/dev/uinput`, for which Valve ships `60-cecd-uinput.rules` saying exactly that,
and nothing else. `uaccess` is an ACL that follows **whoever holds the seat**,
so a daemon deliberately living outside every session is refused by both, while
reporting itself `active` and publishing nothing.

Whoever holds the seat while the picker is up is the greeter, as user `sddm`.
So the answer is the one the OS already implies: **the greeter gets its own
cecd**, in its own session, where the ACL already points.

```sh
ln -sf /usr/lib/systemd/user/cecd.service \
       ~sddm/.config/systemd/user/default.target.wants/cecd.service
```

One symlink, no linger, no group, no udev rule, no permission that was not
already granted. Each session has an instance while it holds the seat: Valve's
in the user's, this one in the greeter's.

Verified on a Steam Machine, at the picker, with no user session in existence:

```
INFO cecd::system: Found cec device at /dev/cec0
N: Name="cecd cros-ec-cec"   H: Handlers=kbd event21
```

**The greeter's compositor picks such a device up.** This was the part left
unproven, because it needs a finger on a remote. It does not, quite: what
matters is the *kind* of device, and one can be conjured — see the controller
above, which is the same experiment with the same answer. cecd's device is a
uinput keyboard, created by root, appearing after the greeter did, and that
drives the picker.

What remains untested is CEC itself end to end, which needs a button pressed on
a television. The VM has a virtual CEC adapter (`vivid`) and cecd attaches to it
and publishes its uinput keyboards, but the two virtual adapters are not on a
shared bus, so no message can be made to arrive. Everything downstream of that
arrival is proven.

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

This is why the picker needs nothing for controller support: it runs where Steam
is not alive, which is exactly the state in which the puck behaves as a keyboard
and mouse. The greeter is more firmly in that state than the old picker session
was, not less.

A bridge that converts joystick events into keys (evdev to uinput) was written
and then deleted: it answered a problem that does not exist on this hardware. If
a pad that has no lizard mode ever needs supporting, write it then — and against
the stdlib, since stock SteamOS has no python-evdev.

## Whichever input was used last wins

A controller is not only a controller: the Steam Controller's right trackpad is
a mouse, and the puck publishes it as one. So a thumb resting on the pad emits
motion the whole time, which would drag the selection around under the d-pad and
leave a cursor sitting on the television.

The picker therefore tracks which input is in use. Any key — from a keyboard,
from the pad in lizard mode, or from the TV remote through `cecd` — hides the
cursor and stops hover from touching the selection. Real pointer movement, more
than about eight design pixels, brings it back and hands the selection to
whatever it is over.

The threshold matters: the compositor delivers a motion event for the cursor it
parks in the middle of the screen at startup, so anything simpler would show a
cursor nobody asked for and preselect the middle card.

**And it has to be measured in scene coordinates**, which is not a detail. A
card scales when the selection reaches it, so it moves *under* a stationary
cursor; in that card's own frame the pointer has then travelled, and a threshold
applied there fires on a pointer nobody touched. What that looked like on the
machine: with a cursor resting anywhere on the shelf, every d-pad press moved
the selection and was instantly handed back to the card under the cursor, so the
shelf could not be driven at all. Given that the Steam Controller publishes its
trackpad as a mouse, a cursor resting on the shelf is the normal state of
things, not an unlucky one.

One baseline for the whole shelf, in scene coordinates, and a cursor nobody is
touching keeps the same position however much the shelf rearranges itself.
Reproduced in the VM by parking a uinput pointer on a card and pressing right
twice, which is also how the fix was checked.

## What is not there

**No virtual keyboard.** Stock SteamOS loads qtvirtualkeyboard into the greeter,
for typing a password. This one never asks for a password, so `InputMethod=` is
cleared — one less thing to load before the room can see anything.
