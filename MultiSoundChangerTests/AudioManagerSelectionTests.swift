//
//  AudioManagerSelectionTests.swift
//  MultiSoundChangerTests
//
//  Selection SSOT invariants, device-row rendering, and the launch-restore fallback chain.
//  `selection` is private, so it's asserted through its persisted mirror (UserDefaults) and through
//  the HAL side-effects recorded by FakeAudio.
//

import Testing
@testable import MultiSoundChanger2

@Suite struct AudioManagerSelectionTests {

    private func persistedSelection(_ scene: TestScene) -> [String] {
        return scene.defaults.stringArray(forKey: Constants.UserDefaultsKeys.selectedDeviceUIDs) ?? []
    }

    // MARK: toggleSelection — the set never empties

    @Test func toggleRejectsUncheckingTheLastDevice() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A")

        let changed = scene.manager.toggleSelection(uid: "A")

        #expect(changed == false)
        #expect(persistedSelection(scene) == ["A"])
    }

    @Test func toggleAppendsNewDeviceAtEnd() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A")

        let changed = scene.manager.toggleSelection(uid: "B")

        #expect(changed == true)
        // Order matters: index 0 is the master candidate when the aggregate is (re)built.
        #expect(persistedSelection(scene) == ["A", "B"])
    }

    @Test func toggleRemovesFromMiddle() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
            audio.addOutputDevice(id: 3, uid: "C", name: "C")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A")
        scene.manager.toggleSelection(uid: "B")
        scene.manager.toggleSelection(uid: "C") // [A, B, C]

        scene.manager.toggleSelection(uid: "B")

        #expect(persistedSelection(scene) == ["A", "C"])
    }

    // MARK: selectSingle

    @Test func selectSingleCollapsesToOneDevice() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A")
        scene.manager.toggleSelection(uid: "B") // multi [A, B] -> aggregate

        scene.manager.selectSingle(uid: "B")

        #expect(persistedSelection(scene) == ["B"])
    }

    @Test func selectSingleTearsDownAggregateWhenLeavingMultiOutput() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        defer { scene.cleanup() }
        _ = scene.manager.currentDeviceRows() // populate deviceIDByUID as an open menu does
        scene.manager.selectSingle(uid: "A")
        scene.manager.toggleSelection(uid: "B") // builds aggregate
        scene.audio.clearCalls()

        scene.manager.selectSingle(uid: "A") // collapse to single

        // Hybrid lifecycle: aggregate destroyed the moment selection collapses below 2.
        #expect(scene.audio.calls.contains { $0.hasPrefix("destroyAggregateDevice") })
    }

    // MARK: currentDeviceRows

    @Test func deviceRowsAreSortedNaturally() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "u10", name: "Device 10")
            audio.addOutputDevice(id: 2, uid: "u2", name: "Device 2")
        }
        defer { scene.cleanup() }

        let rows = scene.manager.currentDeviceRows()

        #expect(rows.map { $0.name } == ["Device 2", "Device 10"])
    }

    @Test func deviceRowsShowUnpluggedSelectionGreyedOut() {
        let scene = makeScene(
            persistedSelection: ["A", "GONE"],
            persistedNames: ["GONE": "Ghost Device"]
        ) { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.defaultOutputDeviceID = 1
        }
        defer { scene.cleanup() }
        scene.manager.restoreSelectionAtLaunch()

        let rows = scene.manager.currentDeviceRows()
        let ghost = rows.first { $0.uid == "GONE" }

        #expect(ghost != nil)
        #expect(ghost?.isSelected == true)
        #expect(ghost?.isAvailable == false)
        #expect(ghost?.name == "Ghost Device") // last known name, not the raw UID
    }

    @Test func deviceRowsPersistNames() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "Speakers")
        }
        defer { scene.cleanup() }

        _ = scene.manager.currentDeviceRows()

        let names = scene.defaults.dictionary(forKey: Constants.UserDefaultsKeys.deviceNamesByUID) as? [String: String]
        #expect(names?["A"] == "Speakers")
    }

    @Test func ownAggregateIsFilteredFromDeviceList() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.createAggregateDevice(name: "own", uid: Constants.Aggregate.uid, subDeviceUIDs: ["A"], masterUID: "A")
        }
        defer { scene.cleanup() }

        let rows = scene.manager.currentDeviceRows()

        #expect(!rows.contains { $0.uid == Constants.Aggregate.uid })
    }

    // MARK: restoreSelectionAtLaunch — fallback chain

    @Test func restoreUsesPersistedSelectionFirst() {
        let scene = makeScene(persistedSelection: ["A"]) { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.defaultOutputDeviceID = 1
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(persistedSelection(scene) == ["A"])
        #expect(scene.audio.calls.contains { $0 == "setOutputDevice(1)" })
    }

    @Test func restoreFallsBackToOrphanAggregateComposition() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
            // A crash-orphaned aggregate survives with its composition, but nothing is persisted.
            audio.createAggregateDevice(name: "own", uid: Constants.Aggregate.uid, subDeviceUIDs: ["A", "B"], masterUID: "A")
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(persistedSelection(scene) == ["A", "B"])
    }

    @Test func restoreFallsBackToSystemDefaultOnFreshInstall() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 7, uid: "DEF", name: "Default")
            audio.defaultOutputDeviceID = 7
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(persistedSelection(scene) == ["DEF"])
    }

    @Test func restoreLeavesSelectionEmptyWhenDefaultHasNoUID() {
        let scene = makeScene { audio in
            audio.defaultOutputDeviceID = 99 // no such device -> no UID
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(persistedSelection(scene).isEmpty)
    }

    // MARK: commitSelectionRoutingAvailable — routing by available count

    @Test func routingWithTwoAvailableBuildsAggregate() {
        let scene = makeScene(persistedSelection: ["A", "B"]) { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(scene.audio.calls.contains { $0.hasPrefix("createAggregateDevice") })
    }

    @Test func routingWithOneAvailableSwitchesDirectly() {
        // Two selected, only one plugged in -> route straight to it, no aggregate.
        let scene = makeScene(persistedSelection: ["A", "GONE"]) { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        #expect(scene.audio.calls.contains { $0 == "setOutputDevice(1)" })
        #expect(!scene.audio.calls.contains { $0.hasPrefix("createAggregateDevice") })
        #expect(persistedSelection(scene) == ["A", "GONE"]) // selection preserved, greyed row kept
    }

    @Test func routingWithNoneAvailableKeepsSelectionButRoutesToDefault() {
        let scene = makeScene(persistedSelection: ["GONE1", "GONE2"]) { audio in
            audio.addOutputDevice(id: 5, uid: "LIVE", name: "Live")
            audio.defaultOutputDeviceID = 5
        }
        defer { scene.cleanup() }

        scene.manager.restoreSelectionAtLaunch()

        // Selection (checkmarks) survives even though nothing is routable right now.
        #expect(persistedSelection(scene) == ["GONE1", "GONE2"])
    }
}
