//
//  Extensions.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 03.04.17.
//  Copyright © 2017 Dmitry Medyuho. All rights reserved.
//

import Cocoa

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension NSImage {
    /// Returns a non-template copy of the image filled with `color`, preserving the silhouette.
    ///
    /// Same technique as `VolumeHUDView.tint`: draw the (template) glyph, then `sourceAtop`-fill it
    /// with the colour. Used both for menu-bar icon tinting (ADR A-9) and for colouring menu
    /// checkmarks/glyphs to match a highlighted row. Deliberately not `contentTintColor`: that
    /// proved unreliable for `NSStatusBarButton` on Tahoe (the tint simply didn't take).
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
