<p align="center">
  <img width="350" height="276" src="https://user-images.githubusercontent.com/8312717/115996670-e6511000-a5e8-11eb-8c46-869378d4df2a.png">
</p>

## MultiSound Changer for macOS — Tahoe / Apple Silicon fork

> **This is a community fork** of [rlxone/MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger),
> which has seen no release since v1.0.1 (April 2021) and neither builds nor works on Apple Silicon
> or macOS Tahoe. It is **not** affiliated with or endorsed by the original author.

A small tool for changing sound volume **even for aggregate devices** cause native sound volume
controller can't change volume of aggregate devices.

Features:
* **Changing sound volume of every device** (even virtual aggregate device volume by changing volume of every device in aggregate device)
* Changing default output device
* Native appearance (follows system light/dark appearance)
* Media keys support
* Runs natively on Apple Silicon and macOS Tahoe

It can be very useful if you're using VoodooHDA with 4.0+ sound on the board, but you can find
another use cases.

## Tahoe / Apple Silicon support

Three separate things were broken. Here is what each one actually was, and what this fork does about
it.

### 1. It didn't build for Apple Silicon

The project shipped a compiled copy of Apple's private `OSD.framework`, and that binary contained
only an x86_64 slice — hence `EXCLUDED_ARCHS = arm64` in the project settings.

**This fork removes the private framework entirely.** The volume HUD is now drawn by the app itself
(see below), so nothing calls `OSDManager` any more and nothing needs to link against it. The app no
longer depends on any private Apple framework, and builds as a universal binary (arm64 + x86_64).

### 2. The volume HUD stopped appearing

Worth being precise, since the popular explanation is wrong: `OSDManager` **is still present** on
Tahoe, and `showImage:...` still accepts the call without crashing. What no longer happens is the
drawing — `OSDUIHelper`, the XPC service behind it, is never spawned, so the call goes nowhere.
(`OSDUIHelper` itself still exists; it moved out of `OSD.framework/XPCServices/` to
`/System/Library/CoreServices/OSDUIHelper.app`.) Apple provides no public API to draw the system HUD.

**This fork draws its own HUD** — a pill near the top of the screen built on `NSVisualEffectView`, so
it follows light/dark appearance. It is deliberately *not* a replica of the old centred chiclet
square: Tahoe shows volume as a compact popover near Control Center, so the old design would read as
dated rather than native.

### 3. Volume keys were swallowed before the app could see them

macOS handles volume keys at the HID layer, *before* any `CGEventTap` can intercept them. That is why
the useless "volume cannot be changed" HUD kept appearing on aggregate devices.

**This fork remaps the volume keys at the driver level** with `hidutil`, from the consumer usage page
onto F18/F19/F20 — which the system ignores and the app picks up instead.

> This has a **system-wide side effect** while the app runs. See [Known limitations](#known-limitations).

## Usage

For example if you want to play 2 or more output devices at the same time you should:
* Create aggregate device in Audio MIDI Setup
* Add all output devices you want to this new aggregate device
* Hide default sound controller icon if enabled (by dragging away or in audio preferences)
* Use our app to control sound volume
* Add our app to startup (if you need)

The app needs **accessibility permission** to observe media keys, and will ask on first launch.

## Installation

Builds are **ad-hoc signed and not notarized** — there is no Apple Developer ID behind this fork, so
Gatekeeper will refuse to open it on first launch. To get past it:

```sh
xattr -cr /Applications/MultiSoundChanger.app
```

Alternatively, allow it in System Settings → Privacy & Security after the first blocked attempt.

## Known limitations

**Volume key remapping can outlive a crash.** The remapping lives in the system, not in this process.
It is reverted on a normal quit and on `SIGTERM`/`SIGINT`, and re-applied cleanly on the next launch —
but nothing can catch `SIGKILL` or a power loss. If the app dies that way and you don't restart it,
your volume keys stay remapped. Fix it by hand with:

```sh
hidutil property --set '{"UserKeyMapping":[]}'
```

The remapping does not survive a reboot either, so restarting also clears it.

**Your own key remappings are safe.** `hidutil` replaces the entire `UserKeyMapping` list, so a naive
implementation would wipe remappings you set up yourself (Caps Lock → Escape and friends). This fork
reads the current list, keeps everyone else's entries, and removes only its own on exit.

**macOS 11.0 or later.** Raised from 10.10: the HUD uses SF Symbols (macOS 11+), and 11.0 is also the
earliest macOS running on Apple Silicon.

**Intel builds are compiled but lightly tested.** The universal binary includes an x86_64 slice and it
has been exercised under Rosetta 2 — but not on real Intel hardware.

## Building

Requires **Xcode 26 or later**. Command Line Tools alone are *not* enough: the project uses
storyboards and an asset catalog, which need `ibtool`/`actool`, and those ship only with full Xcode.

```sh
xcodebuild -project MultiSoundChanger.xcodeproj -scheme MultiSoundChanger -configuration Release build
```

CocoaPods is gone — dependencies are vendored. Don't run `pod install`.
[SwiftLint](https://github.com/realm/SwiftLint) is optional: `brew install swiftlint`.

## Credits

This fork stands on other people's work.

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
* This project is released under the Apache 2.0 licence. See LICENCE
