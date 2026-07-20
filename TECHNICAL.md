# Technical notes

Implementation details, platform limitations and build instructions for MultiSound Changer. For what
the app does and how to use it, see the [README](README.md).

## How it works

macOS won't let you adjust the volume of aggregate / multi-output devices — its built-in slider is
greyed out for them. The app works around this by setting the volume of **every sub-device inside the
aggregate at once**, which is the one thing the system control can't do.

Two lower-level mechanisms make the rest of it work:

* **Media keys via `hidutil`.** macOS handles volume keys at the HID layer, *before* any `CGEventTap`
  can see them, so a user-space app can't intercept them normally. The app remaps the consumer-usage
  volume keys onto F18/F19/F20 with `hidutil` — which the system ignores and the app picks up
  instead. The remap is applied only while a media-key tap is actually live, and reverted on quit.
* **A managed Multi-Output device.** Ticking several outputs builds a single aggregate Multi-Output
  device with a fixed UID, visible system-wide (`private: 0`) so other apps' sound can reach it too.
  On every launch the app looks it up by that UID and reuses it instead of creating duplicates.

## What changed from the original

This is a community fork of [rlxone/MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger),
unmaintained since v1.0.1 (April 2021), which no longer builds or runs on Apple Silicon or macOS
Tahoe. It is **not** affiliated with or endorsed by the original author.

Three separate things were broken; here is what each one was and what this fork does about it.

### 1. It didn't build for Apple Silicon

The project shipped a compiled copy of Apple's private `OSD.framework`, and that binary contained
only an x86_64 slice — hence `EXCLUDED_ARCHS = arm64` in the project settings.

**This fork removes the private framework entirely.** The volume HUD is now drawn by the app itself,
so nothing calls `OSDManager` any more and nothing needs to link against it. The app no longer depends
on any private Apple framework, and builds as a universal binary (arm64 + x86_64).

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

### Also new in this fork

The multi-output picker, follow-the-system-output, hide/tint of the menu-bar icon, launch at login,
and 10-language localization are all new here, on top of the three fixes above.

## Known limitations

**Volume key remapping can outlive a crash.** The `hidutil` remap lives in the system, not in this
process — that is inherent to how it works, since the keys have to be caught below `CGEventTap`. It is
reverted on a normal quit and on `SIGTERM`/`SIGINT`, and re-applied cleanly on the next launch — but
nothing can catch `SIGKILL` or a power loss. If the app dies that way and you don't restart it, your
volume keys stay remapped. Fix it by hand with:

```sh
hidutil property --set '{"UserKeyMapping":[]}'
```

The remapping does not survive a reboot either, so restarting also clears it.

**The managed Multi-Output device can outlive a crash, for the same reason.** It has to be visible
system-wide (`private: 0`) so that other apps' sound can reach it too — which means it also survives
if the process dies unexpectedly. On every launch the app looks for it by a fixed UID and reuses it
instead of creating a duplicate. If you ever remove the app for good and want to clean up after it,
delete the **"MultiSoundChanger2 Output"** device by hand in Audio MIDI Setup.

**Hiding the system volume icon relies on an undocumented Control Center preference**
(`com.apple.controlcenter Sound`). The app reads, saves and restores whatever value was already there
— it never hardcodes a value to restore — but Apple could rename or remove this key in a future macOS
release, at which point hiding/restoring will simply stop working (logged, not a crash). To revert by
hand:

```sh
defaults -currentHost write com.apple.controlcenter Sound -int 16
killall ControlCenter
```

(`16` is what "Always Show" typically maps to on most Macs — not a guaranteed universal value; if it
doesn't bring the icon back, check Control Center settings directly.)

**Your own key remappings are safe.** `hidutil` replaces the entire `UserKeyMapping` list, so a naive
implementation would wipe remappings you set up yourself (Caps Lock → Escape and friends). This app
reads the current list, keeps everyone else's entries, and removes only its own on exit.

**macOS 11.0 or later.** The HUD uses SF Symbols (macOS 11+), and 11.0 is also the earliest macOS
running on Apple Silicon.

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

## See also

* [README](README.md) — features, usage and installation
* [CHANGELOG](CHANGELOG.md) — release history
* [NOTICE](NOTICE) — full attribution
