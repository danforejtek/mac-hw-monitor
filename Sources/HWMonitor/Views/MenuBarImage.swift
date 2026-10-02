import AppKit

/// Draws status-item images with plain AppKit. A drawing-handler `NSImage` is cheap and
/// appearance-aware: `labelColor` resolves against the menu bar's light/dark appearance at draw time.
/// One `Segment` per metric; the combined item simply draws several segments in a row.
enum MenuBarImage {
    struct Segment {
        var title: String
        var value: String? = nil        // single value under the title (percent items)
        var lines: [String] = []        // two small lines instead (throughput items)
        var series: [([Double], NSColor)]
        var stacked = false
    }

    static let height: CGFloat = 18
    private static let segmentGap: CGFloat = 7
    private static let titleFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    private static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)

    private static var sparkWidth: CGFloat {
        CGFloat(max(16, min(80, UserDefaults.standard.double(forKey: SettingsKey.menuGraphWidth))))
    }

    static func make(_ segments: [Segment], graphs: Bool, labels: Bool) -> NSImage {
        let widths = segments.map { segmentWidth($0, graphs: graphs, labels: labels) }
        let total = widths.reduce(0, +) + segmentGap * CGFloat(max(segments.count - 1, 0)) + 2
        let image = NSImage(size: NSSize(width: max(total, 8), height: height), flipped: false) { _ in
            var x: CGFloat = 1
            for (seg, w) in zip(segments, widths) {
                draw(seg, at: x, graphs: graphs, labels: labels)
                x += w + segmentGap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func textWidth(_ seg: Segment) -> CGFloat {
        if let value = seg.value {
            return max((seg.title as NSString).size(withAttributes: [.font: titleFont]).width,
                       (value as NSString).size(withAttributes: [.font: valueFont]).width).rounded(.up)
        }
        return (seg.lines.map { ($0 as NSString).size(withAttributes: [.font: smallFont]).width }.max() ?? 0).rounded(.up)
    }

    private static func segmentWidth(_ seg: Segment, graphs: Bool, labels: Bool) -> CGFloat {
        (graphs ? sparkWidth : 0) + (graphs && labels ? 3 : 0) + (labels ? textWidth(seg) : 0)
    }

    private static func draw(_ seg: Segment, at start: CGFloat, graphs: Bool, labels: Bool) {
        var x = start
        if graphs {
            drawSparkline(seg.series, stacked: seg.stacked, in: NSRect(x: x, y: 2, width: sparkWidth, height: 14))
            x += sparkWidth + 3
        }
        guard labels else { return }
        if let value = seg.value {
            (seg.title as NSString).draw(at: NSPoint(x: x, y: 9.5), withAttributes: [.font: titleFont, .foregroundColor: NSColor.secondaryLabelColor])
            (value as NSString).draw(at: NSPoint(x: x, y: 0.5), withAttributes: [.font: valueFont, .foregroundColor: NSColor.labelColor])
        } else {
            let w = textWidth(seg)
            let style = NSMutableParagraphStyle(); style.alignment = .right
            let attrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
            var y: CGFloat = 8.5
            for line in seg.lines.prefix(2) {
                (line as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 10), withAttributes: attrs)
                y -= 8.5
            }
        }
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
