import SwiftUI
import Charts

/// Large chart window with 1 Hour / 24 Hours / 7 Days / 30 Days ranges, like iStat's detail view.
struct HistoryWindow: View {
    @ObservedObject var monitor: Monitor
    @AppStorage(SettingsKey.historyRange) private var rangeRaw = HistoryRange.hour.rawValue

    private var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .hour }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Metric", selection: $monitor.historyMetric) {
                    ForEach(Metric.allCases) { m in Label(m.title, systemImage: m.symbol).tag(m) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 420)
                Spacer()
                Picker("Range", selection: $rangeRaw) {
                    ForEach(HistoryRange.allCases) { r in Text(r.title).tag(r.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 360)
            }
            chart
            legend
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 400)
        .onAppear { monitor.panelAppeared() }
        .onDisappear { monitor.panelDisappeared() }
    }

    private var spec: (keys: [(HistoryStore.Key, String, Color)], stacked: Bool, max: Double?, label: (Double) -> String) {
        switch monitor.historyMetric {
        case .cpu: return ([(.cpuUser, "User", Palette.user), (.cpuSystem, "System", Palette.system)], true, 100, { String(format: "%.0f%%", $0) })
        case .gpu: return ([(.gpu, "GPU", Palette.gpu)], false, 100, { String(format: "%.0f%%", $0) })
        case .memory: return ([(.memUsed, "Used", Palette.memory), (.memPressure, "Pressure", Palette.pressure)], false, 100, { String(format: "%.0f%%", $0) })
        case .disk: return ([(.diskRead, "Read", Palette.diskRead), (.diskWrite, "Write", Palette.diskWrite)], false, nil, { Fmt.rate($0) })
        case .network: return ([(.netIn, "Download", Palette.netIn), (.netOut, "Upload", Palette.netOut)], false, nil, { Fmt.rate($0) })
        }
    }

    private var chart: some View {
        let now = monitor.snapshot.timestamp
        let r = range
        let tierInterval = [1.0, 60, 600, 3600][r.tier]
        let refresh = max(1, UserDefaults.standard.double(forKey: SettingsKey.refreshInterval))
        let s = spec
        let series = s.keys.map { ChartSeries(name: $0.1, color: $0.2, points: downsample(monitor.history.points($0.0, range: r, now: now), maxPoints: 600)) }
        let format: Date.FormatStyle = {
            switch r {
            case .hour, .day: return .dateTime.hour().minute()
            case .week: return .dateTime.weekday(.abbreviated).day()
            case .month: return .dateTime.month(.abbreviated).day()
            }
        }()
        return TimeChart(series: series, range: now.addingTimeInterval(-r.seconds)...now, stacked: s.stacked, maxValue: s.max,
                         gap: max(tierInterval, refresh) * 3 + 1, showAxes: true, axisFormat: format, valueLabel: s.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var legend: some View {
        let s = spec
        let now = monitor.snapshot.timestamp
        return HStack(spacing: 24) {
            ForEach(s.keys, id: \.1) { key, name, color in
                let pts = monitor.history.points(key, range: range, now: now)
                let avg = pts.isEmpty ? 0 : pts.reduce(0) { $0 + $1.v } / Double(pts.count)
                let peak = pts.map(\.v).max() ?? 0
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                    Text(name).foregroundStyle(.secondary)
                    Text("avg \(s.label(avg))  ·  peak \(s.label(peak))").monospacedDigit()
                }
            }
            Spacer()
            Text("\(range.title) · \(monitor.history.points(s.keys[0].0, range: range, now: now).count) samples")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }
}
