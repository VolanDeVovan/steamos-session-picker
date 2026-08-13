# steamos-session-picker

A boot-time session menu for SteamOS. Instead of logging straight into Game
Mode, the machine lands in a 10-foot menu and you pick where to go — Game Mode,
the desktop, a media centre — with a controller, a TV remote, a keyboard or a
mouse.

![The picker on a television](dev/shots/card-0.png)

## Why

The Steam Machine is sold as a games console, and it is a good one. But look at
what it actually is: a small, quiet Linux computer, permanently attached to the
best screen in the house, woken by a controller you already have in your hand.
That machine could be a media centre, a retro-emulation box, a browser for the
sofa, a Jellyfin or Kodi front end — and the hardware is more than willing.

What is missing is a door. SteamOS boots into Steam and only into Steam, so
everything else has to be smuggled in *through* Steam, which is where the
trouble starts. This project adds the door: a menu, before the session starts,
listing everything the machine can boot into.

It does not install Kodi, or anything else. It gets you to whatever you have
installed, in a way that suits a couch and a television.

## Why not just add Kodi as a non-Steam game

That is the usual advice, and it works in the sense that pictures appear. It
also quietly costs you the two things you probably wanted a media centre for.

**HDR does not survive it.** For HDR to reach the television, three things have
to hold: the compositor must implement colour management, the player must ask
for it, and the session must not be nested inside gamescope. The last one is
where it breaks. Gamescope does not offer colour management to its clients —
there are no server-side `wp_color_management_v1` or `frog_color_management_v1`
globals in it at all. Its one HDR path is `gamescope_swapchain_factory_v2`,
spoken only by a Vulkan WSI layer, which a normal application does not use. So a
Kodi window inside Game Mode is an SDR window, no matter what Kodi itself is
capable of. Someone reported exactly this upstream, from the other direction:
*"Gamescope does support HDR… but that wasn't detected by Kodi"*
([xbmc#27490](https://github.com/xbmc/xbmc/issues/27490)).

**And it is a diminished thing besides.** The same report notes no hardware
decoding out of the box in Game Mode, and that Kodi cannot inhibit Valve's sleep
timers while a film is playing.

Run the same player as **its own session, next to Game Mode instead of inside
it**, and the constraints lift: KWin, which SteamOS already ships, does
implement colour management, so an HDR-capable player can actually get HDR.
Which is fine — except SteamOS gives you no way to choose that session at boot.
Hence this.

## What it does

- **Boots into a menu** rather than straight into Game Mode. The menu *is* the
  login screen — SDDM's own greeter, with a theme — so there is no extra session
  between the display manager and the one you picked, and no wait to see it.
- **Asks for no password**, and does not cheat to avoid one: autologin is off
  and PAM is asked properly, through the same `nopasswdlogin` group Debian and
  Ubuntu ship for this. `sudo` and ssh are untouched.
- **Finds sessions by itself**, because SDDM already knows them all. Installing
  a new session makes it appear on the next boot with nothing edited here — Game
  Mode included, which is just another entry.
- **Takes any input the room has.** The controller works with no gamepad code at
  all: while Steam is not running — and at a login screen it is not — the puck
  presents itself as a plain USB keyboard and mouse. A TV remote arrives the
  same way through SteamOS's own CEC daemon.
- **Reuses Steam's own button.** Steam's "Switch to Desktop" leads here too, so
  there is a way back without rebooting.
- **Looks like it belongs.** It runs immediately before Game Mode, so it uses
  Steam's palette and Big Picture's travelling focus rather than inventing a
  look of its own.

## Install

On the machine:

```sh
curl -fsSL https://raw.githubusercontent.com/VolanDeVovan/steamos-session-picker/main/bootstrap.sh | sh
```

That is the whole installation: it clones the repository into
`/opt/steamos-session-picker` and makes the picker SDDM's login screen. Reboot
and you are in it.

Doing it in one go is safe because the things that go wrong here are visible
and recoverable. A theme that will not load falls back to a stock login screen
with the error on it; a session that will not start returns to the picker.
Neither is a loop.

The one exception is worth knowing before you install: the picker has no
password field, because it never asks for one. If the PAM rule is ever gone —
an OS update that replaces `/etc/pam.d/sddm`, an account taken out of the group
— every card is shown and none of them starts, and the way back in is ssh or a
text console rather than the pad in your hand. `install.sh` refuses to set the
machine up if the module that rule needs is missing, and the picker says which
rule it is when a login is refused.

Run it as yourself, not as root: it asks for sudo once, up front, and elevates
only the handful of commands that touch `/etc`. `sudo ./install.sh` works too —
it sets the machine up for whoever invoked sudo, not for root.

The steps are still separate underneath, which is what you want when changing
anything:

```sh
cd /opt/steamos-session-picker
./install.sh             # the whole thing, same as the one-liner
./install.sh try         # restart SDDM now, to see it without rebooting
./install.sh disable     # back to booting straight into Game Mode
./install.sh update      # git pull, then re-apply
./install.sh uninstall   # remove every trace
./install.sh --no-enable # set up, but keep booting as before
```

Nothing is compiled, no packages are installed, and the read-only rootfs is
never touched: SteamOS already ships `sddm-greeter-qt6` and `kwin_wayland`,
which is the entire runtime.

What lands outside the checkout is four small things: one SDDM drop-in that
turns autologin off and says where the theme is, one added line in
`/etc/pam.d/sddm`, one file naming that line so an OS update keeps it, and a
`nopasswdlogin` group with your account in it. Plus, in the greeter account's
own home, two services SteamOS already ships hung off its session: the CEC
daemon, so the television remote works, and powerdevil, so a picker nobody
answers turns the screen off and then sleeps. No system unit, no overlay mount,
no generated session entry — SDDM's theme directory is a setting, so the theme
is read straight out of the checkout. Details in
[docs/install.md](docs/install.md).

## Adding a session

There is nothing to add here. Drop a `.desktop` file where SDDM looks for
sessions — `/usr/share/wayland-sessions`, `/usr/local/share/wayland-sessions`,
or the `xsessions` equivalents — and the picker lists it, using the entry's
`Name` and `Comment`. That is SDDM's own session list, so if your session shows
up in any other login screen it shows up here.

One entry is left out of it: a stock machine has two KDE sessions, and
`plasmax11.desktop` — the X11 twin of the Wayland session SteamOS itself
defaults to — is named in `hide=` in the theme's `theme.conf`. Put `hide=` in a
`theme.conf.user` beside it to have it back, or to hide something else.

## How it works

| Topic | |
|---|---|
| How SteamOS decides which session to start, and the pitfalls | [docs/mechanism.md](docs/mechanism.md) |
| Installing on an immutable OS, and what survives updates | [docs/install.md](docs/install.md) |
| Controller, TV remote, keyboard, mouse | [docs/input.md](docs/input.md) |
| How this is developed and tested, and what a VM cannot answer | [docs/development.md](docs/development.md) |

## Status

Early. Install, boot into the picker, choose with the keyboard, and land in the
chosen session with no password — all verified end to end on a stock SteamOS
image, in a virtual machine ([`steamos-vm/`](steamos-vm/README.md)). The layout
is checked by rendering it headlessly at 720p, 1080p and 4K, and the interface
has been driven with a real Steam Controller.

What has **not** happened yet is a run on a Steam Machine: this theme has never
been installed on one. Game Mode and the television — CEC end to end, HDR — are
the parts a VM cannot answer at all. Everything in `docs/` marks plainly which
facts were read off real hardware and which were not.
