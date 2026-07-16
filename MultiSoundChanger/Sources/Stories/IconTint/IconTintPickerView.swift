//
//  IconTintPickerView.swift
//  MultiSoundChanger
//
//  Opt-in menu-bar icon colouring (ADR A-9). Each swatch shows the *actual* status-bar icon
//  rendered in that colour — so the user sees how the menu-bar icon will look, not an abstract
//  colour dot. Tinting is done by rendering a colour-filled copy of the template image
//  (`NSImage.tinted(with:)`), not `contentTintColor`: the latter did not visibly tint the status
//  item on Tahoe.
//

import Cocoa

// MARK: - IconTint

enum IconTint: String, CaseIterable {
    case `default`
    case blue
    case orange
    case green
    case purple
    case pink

    /// `nil` means "leave it as a template image" — the system draws it black/white to match the
    /// menu-bar appearance, i.e. the untinted look.
    var color: NSColor? {
        switch self {
        case .default:
            return nil
        case .blue:
            return .systemBlue
        case .orange:
            return .systemOrange
        case .green:
            return .systemGreen
        case .purple:
            return .systemPurple
        case .pink:
            return .systemPink
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .default:
            return Strings.iconTintDefault
        case .blue:
            return Strings.iconTintBlue
        case .orange:
            return Strings.iconTintOrange
        case .green:
            return Strings.iconTintGreen
        case .purple:
            return Strings.iconTintPurple
        case .pink:
            return Strings.iconTintPink
        }
    }

    /// Image to hand to the status-bar button. Template (system-drawn) for `.default`, a
    /// colour-filled non-template copy otherwise.
    func statusBarImage(base: NSImage?) -> NSImage? {
        guard let base = base else {
            return nil
        }
        guard let color = color else {
            base.isTemplate = true
            return base
        }
        return base.tinted(with: color)
    }

    /// Image for the picker swatch. `.default` is shown in the menu's label colour — that's how the
    /// template renders against this (dark or light) menu background, i.e. the untinted preview.
    func swatchImage(base: NSImage?) -> NSImage? {
        return base?.tinted(with: color ?? .labelColor)
    }
}

// MARK: - IconTintSwatchView

final class IconTintSwatchView: NSView {
    let tint: IconTint
    private let baseImage: NSImage?
    private var isSelected: Bool
    private let onSelect: (IconTint) -> Void

    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            needsDisplay = true
        }
    }

    private enum Metrics {
        static let side: CGFloat = 28
        static let glyph: CGFloat = 19
        static let cornerRadius: CGFloat = 5
    }

    init(tint: IconTint, baseImage: NSImage?, isSelected: Bool, onSelect: @escaping (IconTint) -> Void) {
        self.tint = tint
        self.baseImage = baseImage
        self.isSelected = isSelected
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.side, height: Metrics.side))
        setAccessibilityLabel(tint.accessibilityLabel)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 1, dy: 1)
        if isHovering {
            // Same accent highlight as a hovered menu row (device list / standard items).
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: pill, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius).fill()
        } else if isSelected {
            // Neutral persistent marker for the active tint (a coloured glyph on an accent fill
            // would clash, so the resting selection uses a soft grey box instead).
            NSColor.labelColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: pill, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius).fill()
        }

        // While hovering, the glyph goes white on the accent fill — exactly like the white text of a
        // hovered menu row — so the highlight reads consistently; the colour preview is visible in
        // the resting state.
        let image = isHovering ? baseImage?.tinted(with: .white) : tint.swatchImage(base: baseImage)
        guard let image = image else {
            return
        }
        let scale = Metrics.glyph / max(image.size.width, image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(
            x: (bounds.width - drawSize.width) / 2,
            y: (bounds.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: rect)
    }

    override func mouseUp(with event: NSEvent) {
        onSelect(tint)
    }
}

// MARK: - IconTintPickerView

final class IconTintPickerView: NSView {
    private var swatchViews: [IconTintSwatchView] = []

    private enum Metrics {
        static let spacing: CGFloat = 8
        static let height: CGFloat = 30
        static let leadingMargin: CGFloat = 18
    }

    /// `baseImage` is the status-bar glyph to preview in every swatch. `onSelect` persists/applies
    /// the tint and closes the menu — picking a tint is a single-shot action.
    func configure(selected: IconTint, baseImage: NSImage?, onSelect: @escaping (IconTint) -> Void) {
        swatchViews.forEach { $0.removeFromSuperview() }
        swatchViews = []

        var x: CGFloat = Metrics.leadingMargin
        for tint in IconTint.allCases {
            let swatch = IconTintSwatchView(
                tint: tint,
                baseImage: baseImage,
                isSelected: tint == selected,
                onSelect: onSelect
            )
            var swatchFrame = swatch.frame
            swatchFrame.origin = NSPoint(x: x, y: (Metrics.height - swatchFrame.height) / 2)
            swatch.frame = swatchFrame
            addSubview(swatch)
            swatchViews.append(swatch)
            x += swatchFrame.width + Metrics.spacing
        }

        frame = NSRect(x: 0, y: 0, width: x, height: Metrics.height)
    }
}
