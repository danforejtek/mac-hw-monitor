import SwiftUI
import AppKit

enum Palette {
    static let user = Color.blue
    static let system = Color.red
    static let gpu = Color.green
    static let memory = Color.purple
    static let wired = Color(nsColor: .systemTeal)
    static let active = Color.red
    static let compressed = Color.purple
    static let cached = Color.gray.opacity(0.5)
    static let diskRead = Color.cyan
    static let diskWrite = Color.orange
    static let netIn = Color.mint
    static let netOut = Color.pink
    static let load1 = Color.blue
    static let load5 = Color.red
    static let load15 = Color.gray
    static let pressure = Color.blue
    static let chartBackground = Color.primary.opacity(0.06)
}

/// Blue capitalised centred header, as in iStat Menus.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.top, 9).padding(.bottom, 5)
    }
}

/// A titled block in a dropdown, separated from the next by a divider.
struct DropdownSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 4) {
            SectionHeader(title: title)
            content.padding(.horizontal, 12)
        }
        .padding(.bottom, 9)
        Divider()
    }
}

/// Label on the left, value on the right, optional colour swatch.
struct ValueRow: View {
    let label: String
    let value: String
    var color: Color? = nil
    var dim = false
    var body: some View {
        HStack(spacing: 6) {
            if let color { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10) }
            Text(label).foregroundStyle(dim ? .tertiary : .secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(dim ? .secondary : .primary)
        }
        .font(.system(size: 13))
    }
}

struct Meter: View {
    var fraction: Double
    var color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(2, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 9)
    }
}

struct StackedBar: View {
    var segments: [(value: Double, color: Color)]
    var total: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(s.color)
                        .frame(width: max(0, geo.size.width * CGFloat(total > 0 ? min(s.value / total, 1) : 0)))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(Capsule())
        }
        .frame(height: 9)
    }
}

/// Process row with the app icon, as Activity Monitor / iStat show it.
struct ProcessRow: View {
    let process: ProcessSample
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(for: process.path))
                .resizable().frame(width: 16, height: 16)
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 13))
    }
}

final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let generic = NSWorkspace.shared.icon(for: .unixExecutable)

    func icon(for path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        var icon = generic
        if let r = path.range(of: ".app/") {
            icon = NSWorkspace.shared.icon(forFile: String(path[..<r.lowerBound]) + ".app")
        } else if !path.isEmpty, path.hasSuffix(".xpc") || path.contains(".xpc/") {
            icon = NSWorkspace.shared.icon(for: .bundle)
        }
        cache[path] = icon
        return icon
    }
}

/// Common frame + footer of every dropdown; reports visibility to the monitor so charts update.
struct DropdownShell<Content: View>: View {
    @ObservedObject var monitor: Monitor
    let metric: Metric
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) { content }
            }
            .frame(maxHeight: 740)
            DropdownFooter(monitor: monitor, metric: metric)
        }
        .frame(width: 400)
        .onAppear { monitor.panelAppeared() }
        .onDisappear { monitor.panelDisappeared() }
    }
}

struct DropdownFooter: View {
    @ObservedObject var monitor: Monitor
    let metric: Metric
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 18) {
            footerButton("waveform.path.ecg", "Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            footerButton("chart.xyaxis.line", "History") { monitor.openHistory(metric, openWindow: openWindow) }
            Spacer()
            footerButton("gearshape", "Settings") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            footerButton("power", "Quit HW Monitor") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func footerButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless).help(help)
    }
}

extension Monitor {
    func openHistory(_ metric: Metric, openWindow: OpenWindowAction) {
        historyMetric = metric
        openWindow(id: "history")
        NSApp.activate(ignoringOtherApps: true)
    }
}
