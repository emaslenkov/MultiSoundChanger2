//
//  TestScene.swift
//  MultiSoundChangerTests
//
//  Wires an AudioManagerImpl on top of FakeAudio + a real AggregateDeviceManagerImpl + an isolated
//  UserDefaults suite. Deliberately uses the *real* AggregateDeviceManagerImpl rather than a fake:
//  the manager's routing sets `selectedDevice` to the aggregate's id and then reads volume back
//  through `audio`, so both must agree on that id. One coherent in-memory model (the aggregate is
//  really created inside FakeAudio) is more faithful — and less error-prone — than two fakes that
//  could drift. AggregateDeviceManagerImpl is tested directly elsewhere.
//
//  Each scene gets its own UserDefaults suite; call `cleanup()` (via defer) to wipe it — the tests
//  never touch `UserDefaults.standard`.
//

import Foundation
@testable import MultiSoundChanger2

struct TestScene {
    let audio: FakeAudio
    let aggregate: AggregateDeviceManagerImpl
    let defaults: UserDefaults
    let manager: AudioManagerImpl
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Builds a scene. `configure` populates FakeAudio before the manager is created (so the manager's
/// init sees the devices). `persistedSelection`/`persistedNames` seed the suite as a prior launch would.
func makeScene(
    persistedSelection: [String]? = nil,
    persistedNames: [String: String]? = nil,
    configure: (FakeAudio) -> Void = { _ in }
) -> TestScene {
    let audio = FakeAudio()
    configure(audio)

    let suiteName = "io.github.emaslenkov.multisoundchanger2.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    if let persistedSelection = persistedSelection {
        defaults.set(persistedSelection, forKey: Constants.UserDefaultsKeys.selectedDeviceUIDs)
    }
    if let persistedNames = persistedNames {
        defaults.set(persistedNames, forKey: Constants.UserDefaultsKeys.deviceNamesByUID)
    }

    let aggregate = AggregateDeviceManagerImpl(audio: audio)
    let manager = AudioManagerImpl(audio: audio, aggregateDeviceManager: aggregate, defaults: defaults)
    return TestScene(audio: audio, aggregate: aggregate, defaults: defaults, manager: manager, suiteName: suiteName)
}
