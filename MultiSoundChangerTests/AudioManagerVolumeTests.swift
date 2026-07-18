//
//  AudioManagerVolumeTests.swift
//  MultiSoundChangerTests
//
//  Volume fan-out to aggregate sub-devices, the mute threshold, and mute toggling. This is the
//  product's whole point: setting volume on each sub-device of the aggregate individually.
//

import Testing
@testable import MultiSoundChanger2

@Suite struct AudioManagerVolumeTests {

    private func singleScene(volume: [Float] = [0.5, 0.5, 0.5]) -> TestScene {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
        }
        scene.audio.devices[1]?.volume = volume
        _ = scene.manager.currentDeviceRows() // populate deviceIDByUID as an open menu does
        scene.manager.selectSingle(uid: "A")
        return scene
    }

    private func multiScene() -> TestScene {
        let scene = makeScene { audio in
            audio.addOutputDevice(id: 1, uid: "A", name: "A")
            audio.addOutputDevice(id: 2, uid: "B", name: "B")
        }
        _ = scene.manager.currentDeviceRows()
        scene.manager.selectSingle(uid: "A")
        scene.manager.toggleSelection(uid: "B") // [A, B] -> aggregate
        return scene
    }

    // MARK: setSelectedDeviceVolume

    @Test func volumeFansOutToEveryAggregateSubDevice() {
        let scene = multiScene()
        defer { scene.cleanup() }

        scene.manager.setSelectedDeviceVolume(masterChannelLevel: 0.7, leftChannelLevel: 0.7, rightChannelLevel: 0.7)

        #expect(scene.audio.devices[1]?.volume == [0.7, 0.7, 0.7])
        #expect(scene.audio.devices[2]?.volume == [0.7, 0.7, 0.7])
    }

    @Test func volumeBelowThresholdMutes() {
        let scene = singleScene()
        defer { scene.cleanup() }

        // All three channels below muteVolumeLowerbound (0.001) -> mute.
        scene.manager.setSelectedDeviceVolume(masterChannelLevel: 0.0005, leftChannelLevel: 0.0005, rightChannelLevel: 0.0005)

        #expect(scene.audio.devices[1]?.muted == true)
    }

    @Test func volumeAboveThresholdDoesNotMute() {
        let scene = singleScene()
        defer { scene.cleanup() }

        scene.manager.setSelectedDeviceVolume(masterChannelLevel: 0.5, leftChannelLevel: 0.5, rightChannelLevel: 0.5)

        #expect(scene.audio.devices[1]?.muted == false)
    }

    @Test func volumeOnSingleDeviceWritesDirectly() {
        let scene = singleScene()
        defer { scene.cleanup() }

        scene.manager.setSelectedDeviceVolume(masterChannelLevel: 0.3, leftChannelLevel: 0.3, rightChannelLevel: 0.3)

        #expect(scene.audio.devices[1]?.volume == [0.3, 0.3, 0.3])
    }

    // MARK: getSelectedDeviceVolume

    @Test func selectedVolumeIsMaxAcrossChannels() {
        let scene = singleScene(volume: [0.4, 0.2, 0.6])
        defer { scene.cleanup() }

        #expect(scene.manager.getSelectedDeviceVolume() == 0.6)
    }

    @Test func selectedVolumeOnAggregateReadsFirstOutputSubDevice() {
        let scene = multiScene()
        defer { scene.cleanup() }
        scene.manager.setSelectedDeviceVolume(masterChannelLevel: 0.8, leftChannelLevel: 0.8, rightChannelLevel: 0.8)

        #expect(scene.manager.getSelectedDeviceVolume() == 0.8)
    }

    @Test func selectedVolumeIsNilWithoutSelectedDevice() {
        let scene = makeScene()
        defer { scene.cleanup() }

        #expect(scene.manager.getSelectedDeviceVolume() == nil)
    }

    // MARK: mute

    @Test func toggleMuteMutesAnUnmutedDevice() {
        let scene = singleScene()
        defer { scene.cleanup() }

        scene.manager.toggleMute()

        #expect(scene.audio.devices[1]?.muted == true)
        #expect(scene.manager.isMuted == true)
    }

    @Test func toggleMuteUnmutesAndRestoresVolume() {
        let scene = singleScene(volume: [0.5, 0.5, 0.5])
        defer { scene.cleanup() }
        scene.manager.toggleMute() // mute

        scene.manager.toggleMute() // unmute

        #expect(scene.audio.devices[1]?.muted == false)
        #expect(scene.manager.getSelectedDeviceVolume() == 0.5)
    }

    @Test func muteStateOnAggregateReadsFirstSubDevice() {
        let scene = multiScene()
        defer { scene.cleanup() }
        scene.audio.devices[1]?.muted = true // first sub-device muted

        #expect(scene.manager.isSelectedDeviceMuted() == true)
    }

    @Test func muteIsIndependentFromZeroVolume() {
        // Mute is a state of its own — a device at 0% is not the same as a muted one.
        let scene = singleScene(volume: [0, 0, 0])
        defer { scene.cleanup() }

        #expect(scene.manager.isSelectedDeviceMuted() == false)
    }
}
