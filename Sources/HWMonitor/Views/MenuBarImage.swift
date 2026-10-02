import AppKit

/// Draws a status-item image with plain AppKit. A drawing-handler `NSImage` is cheap and
/// appearance-aware: `labelColor` resolves against the menu bar's light/dark appearance at draw time.
enum MenuBarImage {
    static let height: CGFloat = 18
    private static let sparkWidth: CGFloat = 32

    /// Percentage style item: small title above a value, optional (stacked) sparkline.
    static func make(title: String, value: String, series: [([Double], NSColor)], stacked: Bool, graphs: Bool, labels: Bool) -> NSImage {
        let textWidth: CGFloat = labels ? 26 : 0
        let width = (graphs ? sparkWidth + (labels ? 3 : 0) : 0) + textWidth + 4
        let image = NSImage(size: NSSize(width: max(width, 8), height: height), flipped: false) { _ in
            var x: CGFloat = 2
            if graphs {
                drawSparkline(series, stacked: stacked, in: NSRect(x: x, y: 2, width: sparkWidth, height: 14))
                x += sparkWidth + 3
            }
            if labels {
                (title as NSString).draw(at: NSPoint(x: x, y: 9.5), withAttributes:
                    [.font: NSFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
                (value as NSString).draw(at: NSPoint(x: x, y: 0.5), withAttributes:
                    [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: NSColor.labelColor])
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Throughput style item: two small right-aligned lines, optional two-line sparkline.
    static func make(title: String, lines: [String], series: [([Double], NSColor)], graphs: Bool, labels: Bool) -> NSImage {
        let textWidth: CGFloat = labels ? 58 : 0
        let width = (graphs ? sparkWidth + (labels ? 3 : 0) : 0) + textWidth + 4
        let image = NSImage(size: NSSize(width: max(width, 8), height: height), flipped: false) { _ in
            var x: CGFloat = 2
            if graphs {
                drawSparkline(series, stacked: false, in: NSRect(x: x, y: 2, width: sparkWidth, height: 14))
                x += sparkWidth + 3
            }
            if labels {
                let style = NSMutableParagraphStyle(); style.alignment = .right
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                                                            .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
                var y: CGFloat = 8.5
                for line in lines.prefix(2) {
                    (line as NSString).draw(in: NSRect(x: x, y: y, width: textWidth, height: 10), withAttributes: attrs)
                    y -= 8.5
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawSparkline(_ series: [([Double], NSColor)], stacked: Bool, in rect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        guard let n = series.first?.0.count, n >= 2 else { return }
        var base = [Double](repeating: 0, count: n)
        for (values, color) in series {
            guard values.count == n else { continue }
            let tops = zip(base, values).map { min($0 + $1, 1) }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * CGFloat(base[0])))
            for (i, v) in tops.enumerated() {
                path.line(to: NSPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1), y: rect.minY + rect.height * CGFloat(v)))
            }
            for i in stride(from: n - 1, through: 0, by: -1) {
                path.line(to: NSPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1), y: rect.minY + rect.height * CGFloat(stacked ? base[i] : 0)))
            }
            path.close()
            color.withAlphaComponent(stacked ? 0.9 : 0.45).setFill()
            path.fill()
            if !stacked {
                let line = NSBezierPath(); line.lineWidth = 1
                for (i, v) in tops.enumerated() {
                    let p = NSPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1), y: rect.minY + rect.height * CGFloat(v))
                    i == 0 ? line.move(to: p) : line.line(to: p)
                }
                color.setStroke(); line.stroke()
            }
            if stacked { base = tops }
        }
    }
}
