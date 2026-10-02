import SwiftUI
import Charts

struct ChartSeries: Identifiable {
    let name: String
    let color: Color
    var points: [HPoint]
    var id: String { name }
}

/// Area chart over timestamped points. Stacked for CPU user+system, unstacked otherwise.
/// Series are split at gaps (sleep, app not running) so nothing is drawn across them.
struct TimeChart: View {
    var series: [ChartSeries]
    var range: ClosedRange<Date>
    var stacked = false
    var maxValue: Double? = 100
    var gap: Double = 5
    var showAxes = false
    var axisFormat: Date.FormatStyle = .dateTime.hour().minute()
    var valueLabel: (Double) -> String = { String(format: "%.0f%%", $0) }
    var lineOnly = false

    private var yMax: Double {
        if let m = maxValue { return m }
        let peak: Double
        if stacked {
            // Approximate stacked peak by the max of per-index sums.
            let n = series.map { $0.points.count }.max() ?? 0
            peak = (0..<n).map { i in series.reduce(0) { $0 + (i < $1.points.count ? $1.points[i].v : 0) } }.max() ?? 0
        } else {
            peak = series.map { $0.points.map(\.v).max() ?? 0 }.max() ?? 0
        }
        return max(peak * 1.15, 1)
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(Array(segments(s.points, gap: gap).enumerated()), id: \.offset) { segIndex, seg in
                    ForEach(seg, id: \.t) { p in
                        if lineOnly {
                            LineMark(x: .value("Time", p.date), y: .value(s.name, p.v), series: .value("Segment", "\(s.name)#\(segIndex)"))
                                .foregroundStyle(by: .value("Series", s.name))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.monotone)
                        } else {
                            AreaMark(x: .value("Time", p.date), y: .value(s.name, p.v),
                                     series: .value("Segment", "\(s.name)#\(segIndex)"),
                                     stacking: stacked ? .standard : .unstacked)
                                .foregroundStyle(by: .value("Series", s.name))
                                .opacity(stacked ? 0.95 : 0.55)
                                .interpolationMethod(.monotone)
                            if !stacked {
                                LineMark(x: .value("Time", p.date), y: .value(s.name, p.v), series: .value("Segment", "\(s.name)#\(segIndex)"))
                                    .foregroundStyle(by: .value("Series", s.name))
                                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: range)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            if showAxes {
                AxisMarks(values: .automatic(desiredCount: 8)) {
                    AxisGridLine(); AxisTick()
                    AxisValueLabel(format: axisFormat)
                }
            }
        }
        .chartYAxis {
            if showAxes {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(valueLabel(d)) } }
                }
            }
        }
        .chartPlotStyle { $0.background(Palette.chartBackground) }
    }
}

/// Dropdown-sized chart of the last `seconds` seconds, clickable to open the history window.
struct RecentChart: View {
    @ObservedObject var monitor: Monitor
    let metric: Metric
    var keys: [(HistoryStore.Key, String, Color)]
    var stacked = false
    var maxValue: Double? = 100
    var seconds: Double = 180
    var height: CGFloat = 80
    var lineOnly = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = monitor.snapshot.timestamp
        let interval = max(1, UserDefaults.standard.double(forKey: SettingsKey.refreshInterval))
        TimeChart(series: keys.map { ChartSeries(name: $0.1, color: $0.2, points: monitor.history.recent($0.0, seconds: seconds, now: now)) },
                  range: now.addingTimeInterval(-seconds)...now, stacked: stacked, maxValue: maxValue, gap: interval * 3 + 1, lineOnly: lineOnly)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { monitor.openHistory(metric, openWindow: openWindow) }
            .help("Click for 1 hour – 30 days history")
    }
}

/// Per-core stacked bars (user blue / system red), shown beside the CPU chart.
struct CoreBars: View {
    var cores: [CoreLoad]
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, c in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(Palette.system).frame(height: geo.size.height * CGFloat(min(c.system, 100) / 100))
                        Rectangle().fill(Palette.user).frame(height: geo.size.height * CGFloat(min(c.user, 100 - c.system) / 100))
                    }
                }
            }
        }
        .background(Palette.chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
