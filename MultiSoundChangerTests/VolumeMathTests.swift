//
//  VolumeMathTests.swift
//  MultiSoundChangerTests
//
//  The media-key stepping invariant: snap to the 1/16 grid BEFORE stepping, clamp to 0...1 —
//  key presses always land on multiples of 6.25% (docs/architecture.md § Инварианты).
//

import Testing
@testable import MultiSoundChanger2

@Suite struct VolumeMathTests {

    @Test func stepIsOneSixteenth() {
        #expect(VolumeMath.step == 0.0625)
    }

    @Test func snappedRoundsToTheNearestGridPoint() {
        #expect(VolumeMath.snapped(0.5) == 0.5)
        #expect(VolumeMath.snapped(0.51) == 0.5)
        #expect(VolumeMath.snapped(0.97) == 1.0) // 15.52 rounds to 16
        #expect(VolumeMath.snapped(0.04) == 0.0625) // 0.64 rounds to 1
        #expect(VolumeMath.snapped(0.03) == 0.0) // 0.48 rounds to 0
    }

    @Test func increaseSnapsBeforeStepping() {
        // 0.53 snaps to 0.5 first, then steps — so the result is a grid multiple, not 0.53 + step.
        #expect(VolumeMath.increased(from: 0.53) == 0.5625)
    }

    @Test func decreaseSnapsBeforeStepping() {
        #expect(VolumeMath.decreased(from: 0.53) == 0.4375)
    }

    @Test func boundsAreNotOvershot() {
        #expect(VolumeMath.increased(from: 1.0) == 1.0)
        #expect(VolumeMath.decreased(from: 0.0) == 0.0)
    }

    @Test func sixteenStepsSpanTheWholeRange() {
        var volume: Float = 0
        for _ in 0..<16 {
            volume = VolumeMath.increased(from: volume)
        }
        #expect(volume == 1.0)
    }

    @Test func everyResultIsAGridMultiple() {
        for raw in stride(from: Float(0), through: 1, by: 0.013) {
            let up = VolumeMath.increased(from: raw)
            let remainder = (up / VolumeMath.step).rounded() * VolumeMath.step
            #expect(abs(up - remainder) < 0.0001)
        }
    }
}
