import AppKit

/// Menu bar icon for a model download or load with known progress: a ring
/// that fills clockwise around a down arrow. A template image, so it follows
/// the menu bar's appearance.
enum DownloadProgressIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(progress: Double, accessibilityDescription: String) -> NSImage {
        let fraction = min(max(progress, 0), 1)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 1.6
            let ringRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)

            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: ringRect.width / 2,
                    startAngle: 90,
                    endAngle: 90 - 360 * fraction,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            if let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                arrow.draw(in: NSRect(
                    x: center.x - arrow.size.width / 2,
                    y: center.y - arrow.size.height / 2,
                    width: arrow.size.width,
                    height: arrow.size.height
                ))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
