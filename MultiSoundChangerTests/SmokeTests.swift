//
//  SmokeTests.swift
//  MultiSoundChangerTests
//
//  Pipeline smoke: proves the test bundle builds, injects into the host app and sees internal
//  symbols via @testable import. Real coverage starts with the core suites (stage B).
//

import Testing
@testable import MultiSoundChanger2

struct SmokeTests {
    @Test func clampedKeepsValueInsideRange() {
        #expect(5.clamped(to: 0...10) == 5)
    }

    @Test func clampedRaisesValueBelowLowerBound() {
        #expect((-3).clamped(to: 0...10) == 0)
    }

    @Test func clampedLowersValueAboveUpperBound() {
        #expect(42.clamped(to: 0...10) == 10)
    }

    @Test func clampedCollapsesDegenerateRange() {
        #expect(7.clamped(to: 3...3) == 3)
    }

    @Test func clampedWorksOnFloatBounds() {
        #expect(Float(1.5).clamped(to: 0...1) == 1)
        #expect(Float(-0.5).clamped(to: 0...1) == 0)
    }
}
