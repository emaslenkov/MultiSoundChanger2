//
//  VolumeHUD.swift
//  MultiSoundChanger
//
//  Replacement for the private OSD.framework HUD, which no longer draws
//  anything on macOS 26.
//

import Cocoa

final class VolumeHUD {
    static let shared = VolumeHUD()

    private enum Metrics {
        static let width: CGFloat = 250
        static let height: CGFloat = 52
        static let topMargin: CGFloat = 8
        static let visibleInterval: TimeInterval = 1.5
        static let fadeDuration: TimeInterval = 0.4
    }

    private var panel: NSPanel?
    private var hudView: VolumeHUDView?
    private var hideWorkItem: DispatchWorkItem?

    func show(volume: Float) {
        if panel == nil {
            buildPanel()
        }
        guard let panel = panel, let hudView = hudView else {
            return
        }

        hudView.volume = volume
        position(panel)
        hideWorkItem?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.visibleInterval, execute: workItem)
    }

    // MARK: Private

    private func buildPanel() {
        let frame = NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effectView = NSVisualEffectView(frame: frame)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.pillMask(radius: Metrics.height / 2)

        let hudView = VolumeHUDView(frame: effectView.bounds)
        hudView.autoresizingMask = [.width, .height]
        effectView.addSubview(hudView)

        panel.contentView = effectView

        self.panel = panel
        self.hudView = hudView
    }

    private static func pillMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let mask = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }
        let origin = NSPoint(
            x: visibleFrame.midX - Metrics.width / 2,
            y: visibleFrame.maxY - Metrics.height - Metrics.topMargin
        )
        panel.setFrameOrigin(origin)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Metrics.fadeDuration
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.panel?.alphaValue == 0 {
                self?.panel?.orderOut(nil)
            }
        })
    }
}

// MARK: - VolumeHUDView

private final class VolumeHUDView: NSView {
    var volume: Float = 0 {
        didSet {
            needsDisplay = true
        }
    }

    private enum Metrics {
        static let iconSize: CGFloat = 22
        static let iconLeftMargin: CGFloat = 18
        static let trackLeftMargin: CGFloat = 52
        static let trackRightMargin: CGFloat = 58
        static let trackHeight: CGFloat = 6
        static let percentRightMargin: CGFloat = 16
    }

    override func draw(_ dirtyRect: NSRect) {
        drawIcon()
        drawTrack()
        drawPercent()
    }

    private var symbolName: String {
        if volume <= 0 {
            return "speaker.slash.fill"
        } else if volume < 34 {
            return "speaker.wave.1.fill"
        } else if volume < 67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func drawIcon() {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.iconSize, weight: .medium))
        else {
            return
        }
        let tinted = tint(image: image, color: .labelColor)
        let rect = NSRect(
            x: Metrics.iconLeftMargin,
            y: (bounds.height - tinted.size.height) / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: rect)
    }

    private func drawTrack() {
        let trackRect = NSRect(
            x: Metrics.trackLeftMargin,
            y: (bounds.height - Metrics.trackHeight) / 2,
            width: bounds.width - Metrics.trackLeftMargin - Metrics.trackRightMargin,
            height: Metrics.trackHeight
        )
        let radius = Metrics.trackHeight / 2

        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let fillWidth = trackRect.width * CGFloat(min(max(volume, 0), 100)) / 100
        if fillWidth > 0 {
            var fillRect = trackRect
            fillRect.size.width = max(fillWidth, Metrics.trackHeight)
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func drawPercent() {
        let text = "\(Int(volume.rounded()))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.width - Metrics.percentRightMargin - size.width,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }

    private func tint(image: NSImage, color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}
