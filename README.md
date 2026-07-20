<p align="center">
  <img width="440" src="https://raw.githubusercontent.com/emaslenkov/MultiSoundChanger2/master/screenshots/menu.png" alt="MultiSoundChanger2 menu: multi-output device selection, hide system icon, icon tint, and language selection">
</p>

# MultiSound Changer for macOS

A menu-bar app that controls the volume of **aggregate and multi-output devices** — the ones macOS
won't let you adjust, because its built-in volume slider is greyed out for them. It sets the volume of
every sub-device in the aggregate at once, which is the one thing the system control can't do.

Handy if you run VoodooHDA with 4.0+ output, or any other multi-device setup.

## Features

* **Volume for aggregate / multi-output devices.** The core feature: adjust the volume of every
  device inside an aggregate at once, from a single slider in the menu bar or with the media keys.
* **Send sound to several devices at once — straight from the menu.** Tick the outputs you want and
  the app builds and manages a Multi-Output device for you; no more assembling one by hand in Audio
  MIDI Setup. A plain click switches to a single device, **⇧-click** adds/removes devices from the
  set without closing the menu. A device that gets unplugged stays selected and is picked back up
  when it returns.
* **Switch the default output device** right from the menu.
* **Follows the system output.** When macOS switches outputs on its own — AirPods connecting, a pick
  in Control Center, another app taking over — the menu's checkmarks, slider and icon move to the new
  device to match. If you had a multi-output going, it's remembered and rebuilt once the intercepting
  device (e.g. AirPods) disconnects.
* **Tell this app's icon apart from the system one.** Optionally hide the system's own volume icon,
  and/or tint this app's icon (Blue / Orange / Green / Purple / Pink) — both are off by default.
* **Media keys** (volume up / down / mute) drive the selected device, aggregate included.
* **Launch at login.** Optionally start the app automatically when you log in (off by default;
  available on macOS 13+).
* **10 interface languages.** Switch the language straight from the menu (**Language ▶**) with no
  relaunch: English, Русский, Español, Français, 中文, Deutsch, Italiano, Português (Brasil), 日本語,
  한국어. Defaults to **System (follows macOS)**.
* **Its own volume HUD** — a pill near the top of the screen that follows the system light/dark
  appearance.
* **Universal binary** — runs natively on Apple Silicon and Intel, macOS 11+ including Tahoe.

## Usage

### Playing sound on multiple devices at once

Open the menu and use the device list: a plain click switches output to that device; **⇧-click**
(shift-click) toggles it into or out of the current selection without closing the menu, so you can
check several devices in one go. The app creates and manages a single Multi-Output device for you —
there's no need to build one by hand in Audio MIDI Setup any more. At least one device is always
selected; the last checked box can't be unchecked. A device you selected that gets unplugged stays
checked (shown greyed out) and is picked back up automatically once it's back.

### Hiding the system volume icon

This app's menu bar icon sits right next to the system's own volume icon and can be hard to tell
apart from it. Check **"Hide system volume icon"** in the menu to hide the system one while the app
is running — it's restored automatically when you quit. Off by default; the app never touches this
setting unless you turn it on.

### Tinting the menu bar icon

Pick one of the colour swatches in the menu (Blue / Orange / Green / Purple / Pink) to recolour this
app's own icon, as another way to tell it apart from the system one at a glance. Each swatch previews
the actual icon in that colour. "Default" resets it to the normal look. The choice is remembered
across restarts.

### Choosing the interface language

Open **Language** in the menu and pick one of ten languages, or leave it on **System (follows
macOS)** to track your macOS language. The change applies immediately — no restart. Each language is
listed under its own name, sorted alphabetically. The choice is remembered across restarts.

The app needs **accessibility permission** to observe media keys, and will ask on first launch.

## Installation

Builds are **ad-hoc signed and not notarized** — there is no Apple Developer ID behind this project,
so Gatekeeper will refuse to open it on first launch. To get past it:

```sh
xattr -cr /Applications/MultiSoundChanger.app
```

Alternatively, allow it in System Settings → Privacy & Security after the first blocked attempt.

## About this fork

This is a community fork of [rlxone/MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger),
revived for Apple Silicon and macOS Tahoe. It is **not** affiliated with or endorsed by the original
author. For what changed, how it works under the hood, platform limitations and build instructions,
see **[TECHNICAL.md](TECHNICAL.md)**.

## Credits

This project stands on other people's work.

* **[rlxone (Dmitry Medyuho)](https://github.com/rlxone)** — the original MultiSoundChanger.
* **[Jeffrey Reisberg (@sparc5)](https://github.com/rlxone/MultiSoundChanger/pull/41)** — Apple Silicon
  support, custom HUD, `hidutil` key remapping, vendored MediaKeyTap. This fork's starting point.
* **[juniq (@juniqlim)](https://github.com/rlxone/MultiSoundChanger/pull/40)** — volume percentage
  label, mute as a distinct HUD state.
* **[Nicholas Hurden](https://github.com/nhurden/MediaKeyTap)** — MediaKeyTap (MIT).

See [NOTICE](NOTICE) for full attribution and [CHANGELOG.md](CHANGELOG.md) for what changed.

## Inspiration

* [retrography/audioswitch](https://github.com/retrography/audioswitch)

## Licence

This project is released under the Apache 2.0 licence. See [LICENCE](LICENCE).
