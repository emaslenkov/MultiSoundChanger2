//
//  DeviceListView.swift
//  MultiSoundChanger
//
//  Custom NSView menu item that renders the output device list as checkable rows. A plain
//  NSMenuItem closes the menu on click, which would make shift-click-to-add-another-device
//  impossible — so the whole list lives in one view-based item instead (PLAN-multi-output.md, A4).
//
//  Drawn to match a standard AppKit menu item as closely as a custom view can: a rounded, inset
//  highlight pill (not a full-bleed rectangle), white text/checkmark while highlighted, the menu
//  font, and a checkmark gutter that lines the text up with the neighbouring standard items.
//

import Cocoa

// MARK: - DeviceRowView

final class DeviceRowView: NSView {
    private let row: DeviceRow
    private let onSelect: (String, Bool) -> Void

    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            needsDisplay = true
        }
    }

    private enum Metrics {
        static let height: CGFloat = 22
        static let highlightInsetX: CGFloat = 5
        static let highlightInsetY: CGFloat = 1
        static let cornerRadius: CGFloat = 5
        static let checkmarkLeading: CGFloat = 9
        static let checkmarkPointSize: CGFloat = 11
        static let textLeading: CGFloat = 26
        static let textTrailing: CGFloat = 14
    }

    init(row: DeviceRow, onSelect: @escaping (String, Bool) -> Void) {
        self.row = row
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: Metrics.height))
        setAccessibilityLabel(row.name)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    // MARK: Hover + click

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
        let foreground: NSColor = isHovering
            ? .white
            : (row.isAvailable ? .labelColor : .disabledControlTextColor)

        if isHovering {
            let pill = bounds.insetBy(dx: Metrics.highlightInsetX, dy: Metrics.highlightInsetY)
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: pill, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius).fill()
        }

        drawCheckmark(foreground: foreground)
        drawName(foreground: foreground)
    }

    private func drawCheckmark(foreground: NSColor) {
        guard row.isSelected else {
            return
        }
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.checkmarkPointSize, weight: .semibold)
        guard let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .tinted(with: foreground) else {
            return
        }
        let rect = NSRect(
            x: Metrics.checkmarkLeading,
            y: (bounds.height - checkmark.size.height) / 2,
            width: checkmark.size.width,
            height: checkmark.size.height
        )
        checkmark.draw(in: rect)
    }

    private func drawName(foreground: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let name = row.name as NSString
        let textHeight = name.size(withAttributes: attributes).height
        let rect = NSRect(
            x: Metrics.textLeading,
            y: (bounds.height - textHeight) / 2,
            width: max(bounds.width - Metrics.textLeading - Metrics.textTrailing, 0),
            height: textHeight
        )
        name.draw(in: rect, withAttributes: attributes)
    }

    /// A plain click on a greyed (unavailable) row is a no-op — you can't switch default output to
    /// a device that isn't there. Shift-click on it is still allowed: every greyed row is by
    /// construction already selected (see `AudioManagerImpl.currentDeviceRows`), so shift-click can
    /// only ever be "uncheck it", never "check an unavailable device" (decision 5).
    override func mouseUp(with event: NSEvent) {
        let isShiftClick = event.modifierFlags.contains(.shift)
        guard row.isAvailable || isShiftClick else {
            return
        }
        onSelect(row.uid, isShiftClick)
    }
}

// MARK: - DeviceListView

final class DeviceListView: NSView {
    private var rowViews: [DeviceRowView] = []

    private enum Metrics {
        static let rowHeight: CGFloat = 22
        static let initialWidth: CGFloat = 240
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    func configure(rows: [DeviceRow], onSelect: @escaping (String, Bool) -> Void) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []

        for (index, row) in rows.enumerated() {
            let rowView = DeviceRowView(row: row, onSelect: onSelect)
            rowView.frame = NSRect(x: 0, y: CGFloat(index) * Metrics.rowHeight, width: bounds.width, height: Metrics.rowHeight)
            rowView.autoresizingMask = [.width]
            addSubview(rowView)
            rowViews.append(rowView)
        }

        let width = bounds.width > 0 ? bounds.width : Metrics.initialWidth
        let height = Metrics.rowHeight * CGFloat(max(rows.count, 1))
        frame = NSRect(x: 0, y: 0, width: width, height: height)
    }
}
