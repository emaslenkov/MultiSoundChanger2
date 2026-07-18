//
//  AudioManagerReconcileTests.swift
//  MultiSoundChangerTests
//
//  reconcileWithSystemDefault (ADR A-10): the app follows the system default when it changes from
//  outside, remembers a multi-output it was pushed off, and restores it when the interceptor drops.
//  All branches, since this is the most branch-heavy and easily-broken logic in the app.
//
//  External default changes are simulated by writing FakeAudio.defaultOutputDeviceID directly, as
//  the HAL listener would in production.
//

import Testing
@testable import MultiSoundChanger2

@Suite struct AudioManagerReconcileTests {

    private func persistedSelection(_ scene: TestScene) -> [String] {
        return scene.defaults.stringArray(forKey: Constants.UserDefaultsKeys.selectedDeviceUIDs) ?? []
    }

    /// Builds a live multi-output ([A, B] -> aggregate) and returns the scene with A=1, B=2, C=3.
    private func multiOutputScene() -> TestScene {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
            audio.addOutputDevice(id: 3, uid: "C", name: "C")
        }
        scene.manager.selectSingle(uid: "A")
        scene.manager.toggleSelection(uid: "B") // [A, B] -> aggregate, default now on the aggregate
        return scene
    }

    // MARK: false branches (no follow)

    @Test func ignoresOwnAggregateByDeviceID() {
        let scene = multiOutputScene()
        defer { scene.cleanup() }
        // Default is already our aggregate (we just routed to it) — following would loop.
        #expect(scene.manager.reconcileWithSystemDefault() == false)
    }

    @Test func ignoresOwnAggregateByUID() {
        // Aggregate present under our UID as the default, but the manager doesn't own it (deviceID nil):
        // the UID guard must still catch it.
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            let agg = audio.createAggregateDevice(name: "own", uid: Constants.Aggregate.uid, subDeviceUIDs: ["A"], masterUID: "A")
            audio.defaultOutputDeviceID = agg!
        }
        defer { scene.cleanup() }

        #expect(scene.manager.reconcileWithSystemDefault() == false)
    }

    @Test func ignoresDefaultWithoutReadableUID() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.defaultOutputDeviceID = 99 // no such device
        }
        defer { scene.cleanup() }

        #expect(scene.manager.reconcileWithSystemDefault() == false)
    }

    @Test func ignoresEchoOfOwnWrite() {
        // selection == [defaultUID] already: our own write echoing back, not an external change.
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A") // selection [A], default now A

        #expect(scene.manager.reconcileWithSystemDefault() == false)
        #expect(persistedSelection(scene) == ["A"])
    }

    // MARK: follow branches

    @Test func followsExternalDefaultRememberingMultiOutput() {
        let scene = multiOutputScene()
        defer { scene.cleanup() }

        scene.audio.defaultOutputDeviceID = 3 // system switched to C (e.g. AirPods)
        let changed = scene.manager.reconcileWithSystemDefault()

        #expect(changed == true)
        #expect(persistedSelection(scene) == ["C"])
    }

    @Test func followsExternalDefaultFromSingleWithoutRemembering() {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        defer { scene.cleanup() }
        scene.manager.selectSingle(uid: "A") // single, nothing to remember

        scene.audio.defaultOutputDeviceID = 2 // external switch to B
        #expect(scene.manager.reconcileWithSystemDefault() == true)
        #expect(persistedSelection(scene) == ["B"])

        // Nothing was remembered: dropping B and following to A must NOT restore a multi-output.
        scene.audio.removeDevice(id: 2)
        scene.audio.defaultOutputDeviceID = 1
        #expect(scene.manager.reconcileWithSystemDefault() == true)
        #expect(persistedSelection(scene) == ["A"]) // plain follow, not a restore
    }

    // MARK: restore branch

    @Test func restoresRememberedMultiOutputWhenInterceptorDrops() {
        let scene = multiOutputScene()
        defer { scene.cleanup() }

        // Follow onto C (interceptor), remembering [A, B].
        scene.audio.defaultOutputDeviceID = 3
        _ = scene.manager.reconcileWithSystemDefault()
        #expect(persistedSelection(scene) == ["C"])

        // C drops out, system falls back to A.
        scene.audio.removeDevice(id: 3)
        scene.audio.defaultOutputDeviceID = 1
        let changed = scene.manager.reconcileWithSystemDefault()

        #expect(changed == true)
        #expect(persistedSelection(scene) == ["A", "B"]) // remembered multi-output rebuilt
    }

    @Test func manualPickBetweenFollowAndRestoreClearsMemory() {
        let scene = multiOutputScene()
        defer { scene.cleanup() }

        scene.audio.defaultOutputDeviceID = 3 // follow onto C, remember [A, B]
        _ = scene.manager.reconcileWithSystemDefault()

        scene.manager.selectSingle(uid: "C") // explicit manual pick cancels "put the old set back"

        scene.audio.removeDevice(id: 3)
        scene.audio.defaultOutputDeviceID = 1
        let changed = scene.manager.reconcileWithSystemDefault()

        #expect(changed == true)
        #expect(persistedSelection(scene) == ["A"]) // plain follow — memory was cleared, no restore
    }
}
