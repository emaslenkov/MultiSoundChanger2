# Changelog

All notable changes to this fork are documented here.

This project is a community fork of [rlxone/MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger).
Versions below v1.1.0 belong to the upstream project.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] — 2026-07-20

Tagged `v1.5.0`.

### Added

- **Localization — 10 languages, switchable from the menu.** A new `Language ▶` submenu lets you
  pick the interface language: English, Русский, Español, Français, 中文, Deutsch, Italiano,
  Português (Brasil), 日本語, 한국어. The first entry, `System (follows macOS)`, is the default and
  tracks your macOS language. Each language is listed under its own name. Switching is instant — no
  relaunch: the app loads the chosen `.lproj` bundle at runtime and rebuilds the menu. A checkmark
  marks the active language.

- **Unit test suite** — 82 tests covering the app's core logic: device selection invariants (the
  set never empties), single/multi routing and the launch restore chain, every branch of the
  follow-the-system-default reconciliation, volume fan-out to aggregate sub-devices with the mute
  threshold, the managed aggregate lifecycle (orphan reuse, master policy, drift compensation
  ordering), the `hidutil` remap merge that preserves user-defined key mappings, the Control Center
  icon hide/restore state machine, and the media-key volume stepping grid. Tests run as a hosted
  bundle via `xcodebuild test` and in CI on every push and pull request; the host app stays inert
  under tests so a test run never touches the real system.

### Changed

- Internal, behavior-preserving refactoring for testability: injectable `UserDefaults`/shell seams
  (production defaults unchanged), media-key stepping extracted into pure `VolumeMath` functions,
  `hidutil` remap parsing/merging extracted into pure functions, and typo cleanups in internal
  identifiers. No user-facing changes.

### Fixed

- **Menu-bar icon showed "muted" at launch over live audio.** When the app started (especially via
  Launch at login), the menu-bar icon stayed on its lowest/muted glyph until the first volume change,
  even though sound was playing at the real level. The icon now syncs with the selected device's
  actual volume as soon as the menu is built, and refreshes whenever the menu opens.

## [1.4.0] — 2026-07-17

Tagged `v1.4.0`.

### Added

- **Launch at login.** A new "Launch at login" checkbox in the menu, right below "Hide system volume
  icon", starts the app automatically when you log in. It's off by default. The checkmark always
  reflects the real system state rather than a cached preference, so toggling it in System Settings →
  General → Login Items is picked up the next time the menu opens, and the app never re-registers
  itself against a choice you made there. Built on `SMAppService`, which registers the app bundle
  itself — no separate helper, works with the ad-hoc signature. The item is shown only on macOS 13
  and later, where `SMAppService` exists; the deployment target stays macOS 11.

## [1.3.0] — 2026-07-17

Tagged `v1.3.0`.

### Added

- **The app now follows the system output device.** Previously it only ever *set* the default output
  and never listened for it changing, so when the system switched outputs on its own — AirPods
  connecting and macOS auto-switching to them, a pick in Control Center, another app taking over — the
  menu's checkmarks stayed on the old selection while sound already played elsewhere. A listener on
  `kAudioHardwarePropertyDefaultOutputDevice` now reconciles the selection with whatever the system
  considers default, moving the checkmarks, slider and menu-bar icon onto the new device even while
  the menu is closed. The app's own writes are filtered out, so there is no feedback loop.
- **Multi-output is remembered and restored across an interception.** If the system pulls the default
  onto a single device (AirPods) while a ≥2-device multi-output was active, that set is remembered;
  unplugging the interceptor rebuilds the previous multi-output (same aggregate, by fixed UID) instead
  of leaving you on a single device. A manual pick in the menu clears that memory — an explicit choice
  cancels "put the old set back".

## [1.2.0] — 2026-07-16

Tagged `v1.2.0`.

### Added

- **Pick multiple output devices right from the menu.** The app now creates and manages its own
  Multi-Output device (`AggregateDeviceManager`) with a fixed identifier, so playing sound on several
  devices at once no longer requires building an aggregate by hand in Audio MIDI Setup. A plain click
  on a device switches to it; ⇧-click toggles it into or out of the current selection without closing
  the menu. At least one device is always selected. A selected device that gets unplugged stays
  checked (shown greyed out) and is picked back up automatically once it reappears. The selection
  survives app and system restarts; a device orphaned by a crash (`kill -9`) is found by its fixed UID
  and reused on the next launch instead of being duplicated.
- **Hide the system's own volume icon.** Menu checkbox, off by default, applies immediately; restores
  the icon's original state on quit, `SIGTERM`/`SIGINT`, and repairs it on the next launch if the app
  was killed while it was hidden.
- **Tint the menu bar icon.** A row of swatches in the menu (Default plus Blue/Orange/Green/Purple/Pink)
  recolours the existing template icon — no new icon assets, no change to its shape. The tint is a
  rendered colour-filled copy of the glyph (not `contentTintColor`, which does not tint a status-bar
  button on Tahoe). Each swatch previews the actual icon in that colour. Persists across restarts,
  independent of the system icon setting above.
- `ApplicationController.stop()`, called from a clean quit and from the `SIGTERM`/`SIGINT` handlers
  alike, so every system-level change this app makes goes through exactly one teardown path.

### Changed

- The menu-bar volume row is more compact: the numeric percentage label was removed, leaving just the
  slider, which also narrows the menu.

## [1.1.0] — 2026-07-15

First release of this fork, tagged `v1.1.0`.

### Added

- Native Apple Silicon support: builds as a universal binary (arm64 + x86_64).
  Based on [PR #41](https://github.com/rlxone/MultiSoundChanger/pull/41) by Jeffrey Reisberg (@sparc5).
- Custom volume HUD (`VolumeHUD`) replacing the private OSD HUD path, which no longer draws on
  macOS Tahoe. Rendered as a pill near the top of the screen with `NSVisualEffectView`, following
  system light/dark appearance.
  Based on [PR #41](https://github.com/rlxone/MultiSoundChanger/pull/41).
- HID-level volume key remapping (`MediaKeyRemapper`) via `hidutil`, mapping the consumer usage page
  onto F18/F19/F20 so the app can observe keys that macOS otherwise intercepts before any
  `CGEventTap`.
  Based on [PR #41](https://github.com/rlxone/MultiSoundChanger/pull/41).
- Volume percentage label next to the menu bar slider.
  From [PR #40](https://github.com/rlxone/MultiSoundChanger/pull/40) by juniq (@juniqlim).
- Mute is shown as a state of its own in the HUD — a device sitting at 0% is no longer conflated
  with a muted one.
  Concept from [PR #40](https://github.com/rlxone/MultiSoundChanger/pull/40).
- `SIGTERM`/`SIGINT` handlers that revert the key remapping, in addition to
  `applicationWillTerminate`. `SIGKILL` remains uncatchable and is documented in the README.
- `NOTICE` file with full attribution.

### Changed

- **Renamed to MultiSoundChanger2** with bundle identifier `io.github.emaslenkov.multisoundchanger2`,
  so this fork can be installed alongside the original and does not squat on the upstream author's
  identifier. File, folder and scheme names deliberately keep their upstream spelling, to keep future
  merges from upstream cheap.
- **Removed the dependency on Apple's private `OSD.framework` entirely**, rather than replacing the
  x86_64-only binary with a linker stub. Nothing calls `OSDManager` once the HUD is drawn by the app,
  so the framework, its `.tbd` stub and the bridging header import are all gone. The app no longer
  links against any private Apple framework, and is therefore not exposed to Apple removing it.
- Minimum macOS raised from 10.10 to 11.0 — the HUD uses SF Symbols, and 11.0 is the earliest macOS
  on Apple Silicon. The more conservative of the two candidate targets across the upstream PRs.
- `kAudioObjectPropertyElementMaster` → `kAudioObjectPropertyElementMain` (12 occurrences).
  Deprecated since macOS 12; the two are exact synonyms, so behaviour is unchanged.
- `Process.launch()` → `Process.run()`, `Process.launchPath` → `Process.executableURL`, with the
  failure now logged instead of trapping.
- `NSWorkspace.launchApplication(withBundleIdentifier:...)` → `NSWorkspace.openApplication(at:configuration:)`
  (the former is deprecated since macOS 11).
- `protocol X: class` → `protocol X: AnyObject` (8 occurrences), including the vendored MediaKeyTap.
- Dependencies moved off CocoaPods; MediaKeyTap is vendored under `Vendor/`.
  From [PR #41](https://github.com/rlxone/MultiSoundChanger/pull/41).

### Fixed

- **Volume keys are no longer left dead when accessibility permission is missing.** The remapping was
  applied at launch, unconditionally. Without accessibility there is no key tap to handle the
  remapped keys, so the volume keys did nothing at all — the app had taken them from the system and
  then dropped them. Remapping is now tied to the key tap: no permission, no remap, and the keys keep
  working normally until permission is granted (at which point the app picks them up without a
  restart).
- **Logging levels were meaningless.** `Logger.getDebugLine` shadowed its `symbol` parameter with a
  hardcoded `.info`, and `outAndFilePrint` ignored the parameter altogether, hardcoding `.error` for
  stdout and `.info` for the log file. Every message — warnings and errors included — was printed as
  info. Levels now reflect reality, which is what made the two bugs above visible in the first place.
- **Undefined behaviour reading device names.** `getDeviceName` passed `&result` on an ARC-managed
  `CFString` straight to `AudioObjectGetPropertyData`, letting CoreAudio write a +1 retained
  reference over a managed variable. It now reads into an `Unmanaged<CFString>?` and takes ownership
  explicitly, and reports failures instead of silently returning an empty name.
- **Removed dead `getDeviceType`**, which nothing called and which built an `AudioValueTranslation`
  out of pointers escaping their `withUnsafeMutablePointer` closures — invalid the moment they were
  used.
- **`Volume.storyboard` no longer hardcodes the module name.** It pinned `customModule` without
  `customModuleProvider="target"`, so the view controller failed to instantiate — and the app died —
  the moment the product was renamed.
- **`hidutil` remapping no longer destroys the user's own key mappings.** `hidutil property --set`
  replaces the entire `UserKeyMapping` list, so writing three entries blindly wiped any remapping the
  user had configured themselves (Caps Lock → Escape and friends), and reverting to an empty list
  wiped what remained. The remapper now reads the current list, preserves foreign entries, and
  removes only its own.
- **Stale remapping left by a crashed session is now cleaned up on launch.** `apply()` drops its own
  entries before re-adding them, making it idempotent.
- **HUD flicker on rapid repeated key presses.** Showing the HUD assigned `alphaValue` directly while
  a fade-out animation was still running, letting the stale animation drive the panel back to
  transparent. Shows now cancel the in-flight animation, and a superseded fade no longer orders the
  panel out.
- Removed CocoaPods leftovers (`Podfile`) that survived the migration to vendored dependencies.
- Removed a broken `XPCServices` symlink, a stray `.DS_Store` and an orphaned `_CodeSignature`
  directory that came with the vendored copy of `OSD.framework`.

### Known limitations

- Builds are ad-hoc signed, not notarized: Gatekeeper will block the first launch
  (`xattr -cr /Applications/MultiSoundChanger.app`).
- The key remapping cannot be reverted if the process is `SIGKILL`ed; it does not survive a reboot,
  and relaunching the app also repairs it.
- The x86_64 slice is built and exercised under Rosetta 2, but untested on real Intel hardware.

## [1.0.1] — 2021-04-24

Last upstream release. See the
[original repository](https://github.com/rlxone/MultiSoundChanger/releases).
