//
//  AggregateDeviceManagerTests.swift
//  MultiSoundChangerTests
//
//  Direct tests of AggregateDeviceManagerImpl over FakeAudio: orphan reuse, creation-as-last-resort,
//  anti-recursion, and the "without stutter" update ordering (list -> master -> drift).
//

import AudioToolbox
import Testing
@testable import MultiSoundChanger2

private let ownUID = Constants.Aggregate.uid

@Suite struct AggregateDeviceManagerTests {

    private func makeManager(configure: (FakeAudio) -> Void = { _ in }) -> (AggregateDeviceManagerImpl, FakeAudio) {
        let audio = FakeAudio()
        configure(audio)
        return (AggregateDeviceManagerImpl(audio: audio), audio)
    }

    // MARK: findOwnDevice

    @Test func findOwnDeviceReturnsVerifiedAggregate() {
        let (manager, audio) = makeManager()
        audio.addOutputDevice(id: 1, uid: "A", name: "A")
        let created = audio.createAggregateDevice(name: "agg", uid: ownUID, subDeviceUIDs: ["A"], masterUID: "A")

        #expect(manager.findOwnDevice() == created)
        #expect(manager.deviceID == created)
    }

    @Test func findOwnDeviceRejectsNonAggregateWithOurUID() {
        // A plain device that happens to carry our UID must not be adopted.
        let (manager, audio) = makeManager()
        audio.addOutputDevice(id: 5, uid: ownUID, name: "impostor")

        #expect(manager.findOwnDevice() == nil)
        #expect(manager.deviceID == nil)
    }

    @Test func findOwnDeviceReturnsNilWhenAbsent() {
        let (manager, _) = makeManager()
        #expect(manager.findOwnDevice() == nil)
    }

    // MARK: ensureDevice

    @Test func ensureDeviceCreatesWhenNothingExists() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }

        let id = manager.ensureDevice(subDeviceUIDs: ["A", "B"])

        #expect(id != nil)
        #expect(manager.deviceID == id)
        #expect(audio.calls.contains { $0.hasPrefix("createAggregateDevice") })
    }

    @Test func ensureDeviceAdoptsCrashOrphanInsteadOfCreating() {
        // A device from a previous session already exists under our UID — reuse it, don't create.
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.createAggregateDevice(name: "agg", uid: ownUID, subDeviceUIDs: ["A"], masterUID: "A")
        }
        audio.clearCalls()

        _ = manager.ensureDevice(subDeviceUIDs: ["A"])

        #expect(!audio.calls.contains { $0.hasPrefix("createAggregateDevice") })
        #expect(audio.calls.contains { $0.hasPrefix("setAggregateFullSubDeviceList") })
    }

    @Test func ensureDeviceReusesLiveDevice() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A"])
        audio.clearCalls()

        _ = manager.ensureDevice(subDeviceUIDs: ["A", "B"])

        #expect(!audio.calls.contains { $0.hasPrefix("createAggregateDevice") })
    }

    @Test func ensureDeviceReturnsNilForEmptyList() {
        let (manager, _) = makeManager()
        #expect(manager.ensureDevice(subDeviceUIDs: []) == nil)
    }

    @Test func ensureDeviceStripsOwnUIDFromSubList() {
        // Anti-recursion: our own UID must never end up inside the aggregate's own sub-list.
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }

        let id = manager.ensureDevice(subDeviceUIDs: [ownUID, "A", "B"])

        #expect(id != nil)
        #expect(audio.getAggregateFullSubDeviceList(deviceID: id!) == ["A", "B"])
    }

    // MARK: update ordering

    @Test func updateAppliesListThenMasterThenDriftInOrder() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
            audio.addOutputDevice(id: 3, uid: "C", name: "C")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A", "B"]) // master = A
        audio.clearCalls()

        // A drops out -> master must switch; ordering list -> master -> drift.
        manager.update(subDeviceUIDs: ["B", "C"])

        let list = audio.callIndex { $0.hasPrefix("setAggregateFullSubDeviceList") }
        let master = audio.callIndex { $0.hasPrefix("setAggregateMasterSubDevice") }
        let drift = audio.callIndex { $0.hasPrefix("setSubDeviceDriftCompensation") }
        #expect(list != nil && master != nil && drift != nil)
        #expect(list! < master!)
        #expect(master! < drift!)
    }

    @Test func updateAbortsWhenListWriteFails() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A"])
        audio.clearCalls()
        audio.failSetFullSubDeviceList = true

        manager.update(subDeviceUIDs: ["A", "B"])

        #expect(!audio.calls.contains { $0.hasPrefix("setAggregateMasterSubDevice") })
        #expect(!audio.calls.contains { $0.hasPrefix("setSubDeviceDriftCompensation") })
    }

    @Test func updateKeepsMasterWhileItStaysInSet() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A"]) // master = A
        audio.clearCalls()

        manager.update(subDeviceUIDs: ["A", "B"]) // A still present

        #expect(!audio.calls.contains { $0.hasPrefix("setAggregateMasterSubDevice") })
    }

    @Test func updateSwitchesMasterWhenItDropsOut() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A"]) // master = A
        audio.clearCalls()

        manager.update(subDeviceUIDs: ["B"]) // A gone

        #expect(audio.calls.contains { $0 == "setAggregateMasterSubDevice(\(manager.deviceID!), B)" })
    }

    @Test func updateEnablesDriftOnNonMastersOnly() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = manager.ensureDevice(subDeviceUIDs: ["A"]) // master = A (id 1)

        // On creation drift lives in the create description (not modelled by FakeAudio); the explicit
        // setSubDeviceDriftCompensation pass runs in update(). Add B and check the split.
        manager.update(subDeviceUIDs: ["A", "B"])

        // Drift disabled on master (id 1), enabled on non-master (id 2).
        #expect(audio.driftCompensation[1] == false)
        #expect(audio.driftCompensation[2] == true)
    }

    // MARK: destroy

    @Test func destroyClearsStateAndCallsHAL() {
        let (manager, audio) = makeManager { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
        }
        let id = manager.ensureDevice(subDeviceUIDs: ["A"])
        audio.clearCalls()

        manager.destroy()

        #expect(manager.deviceID == nil)
        #expect(audio.calls.contains { $0 == "destroyAggregateDevice(\(id!))" })
    }

    @Test func destroyIsNoOpWhenNothingOwned() {
        let (manager, audio) = makeManager()
        manager.destroy()
        #expect(!audio.calls.contains { $0.hasPrefix("destroyAggregateDevice") })
    }
}
