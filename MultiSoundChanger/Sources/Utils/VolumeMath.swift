//
//  VolumeMath.swift
//  MultiSoundChanger
//
//  The media-key volume arithmetic, extracted as pure functions so the product invariant is
//  unit-tested: the current volume snaps to the 1/16 grid BEFORE the step is applied, which is why
//  key presses always land on multiples of 6.25% no matter where the slider left the volume.
//  Scale here is the internal 0...1 (see docs/architecture.md — conversion to percent is the
//  callers' responsibility).
//

import Foundation

enum VolumeMath {
    static let step: Float = 1 / Float(Constants.chicletsCount)

    /// The nearest point of the 1/16 grid.
    static func snapped(_ volume: Float) -> Float {
        return (volume / step).rounded() * step
    }

    static func increased(from volume: Float) -> Float {
        return (snapped(volume) + step).clamped(to: 0...1)
    }

    static func decreased(from volume: Float) -> Float {
        return (snapped(volume) - step).clamped(to: 0...1)
    }
}
