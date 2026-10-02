import Foundation

/// One timestamped sample (unix seconds, value).
struct HPoint: Codable, Equatable {
    var t: Double
    var v: Double
    var date: Date { Date(timeIntervalSince1970: t) }

    init(t: Double, v: Double) { self.t = t; self.v = v }

    // Stored compactly as [t, v] with limited precision to keep history.json small.
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(Double.self); v = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode((t * 10).rounded() / 10); try c.encode((v * 100).rounded() / 100)
    }
}

/// A time range shown in the history window. Each range reads from the tier whose
/// resolution fits it (1 s / 1 min / 10 min / 1 h).
enum HistoryRange: String, CaseIterable, Identifiable {
    case hour, day, week, month
    var id: String { rawValue }
    var title: String {
        switch self { case .hour: "1 Hour"; case .day: "24 Hours"; case .week: "7 Days"; case .month: "30 Days" }
    }
    var seconds: Double {
        switch self { case .hour: 3600; case .day: 86400; case .week: 7 * 86400; case .month: 30 * 86400 }
    }
    var tier: Int { HistoryRange.allCases.firstIndex(of: self)! }
}

/// Bucketed averages at one resolution.
struct Tier: Codable {
    let interval: Double
    let capacity: Int
    var points: [HPoint] = []
    var bucket: Double = -1
    var sum: Double = 0
    var count: Int = 0
    var lastT: Double = 0

    init(interval: Double, capacity: Int) { self.interval = interval; self.capacity = capacity }

    mutating func add(_ v: Double, at t: Double) {
        let b = (t / interval).rounded(.down)
        if b != bucket { flush(); bucket = b }
        sum += v; count += 1; lastT = t
    }

    mutating func flush() {
        guard count > 0 else { return }
        points.append(HPoint(t: (bucket + 0.5) * interval, v: sum / Double(count)))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
        sum = 0; count = 0
    }

    /// Stored points plus the bucket still being accumulated.
    func series(since: Double) -> [HPoint] {
        var out = points.drop { $0.t < since }.map { $0 }
        // The open bucket is placed at its latest sample so it never sits in the future.
        if count > 0 { out.append(HPoint(t: min((bucket + 0.5) * interval, lastT), v: sum / Double(count))) }
        return out
    }
}

struct MetricSeries: Codable {
    var tiers: [Tier] = [
        Tier(interval: 1, capacity: 3600),          // 1 hour at 1 s
        Tier(interval: 60, capacity: 1440),         // 24 hours at 1 min
        Tier(interval: 600, capacity: 1008),        // 7 days at 10 min
        Tier(interval: 3600, capacity: 720),        // 30 days at 1 h
    ]
    mutating func add(_ v: Double, at t: Double) { for i in tiers.indices { tiers[i].add(v, at: t) } }
}

/// Multi-resolution history for every charted metric, persisted to Application Support so the
/// 24 h / 7 d / 30 d views survive restarts.
final class HistoryStore {
    enum Key: String, CaseIterable {
        case cpuUser = "cpu.user", cpuSystem = "cpu.system"
        case gpu = "gpu"
        case memUsed = "mem.used"            // percent
        case memPressure = "mem.pressure"
        case diskRead = "disk.read", diskWrite = "disk.write"
        case netIn = "net.in", netOut = "net.out"
        case load1 = "load.1", load5 = "load.5", load15 = "load.15"
    }

    private var series: [String: MetricSeries] = [:]
    private var lastSave = Date()
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HWMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() { load() }

    func add(_ key: Key, _ value: Double, at date: Date = Date()) {
        var s = series[key.rawValue] ?? MetricSeries()
        s.add(value, at: date.timeIntervalSince1970)
        series[key.rawValue] = s
    }

    /// Points for a key over a range, read from the matching tier.
    func points(_ key: Key, range: HistoryRange, now: Date = Date()) -> [HPoint] {
        guard let s = series[key.rawValue] else { return [] }
        return s.tiers[range.tier].series(since: now.timeIntervalSince1970 - range.seconds)
    }

    /// Latest `seconds` seconds at 1 s resolution (for the dropdown charts).
    func recent(_ key: Key, seconds: Double, now: Date = Date()) -> [HPoint] {
        guard let s = series[key.rawValue] else { return [] }
        return s.tiers[0].series(since: now.timeIntervalSince1970 - seconds)
    }

    func saveIfDue(interval: TimeInterval = 60) {
        if Date().timeIntervalSince(lastSave) >= interval { save() }
    }

    func save() {
        lastSave = Date()
        let snapshot = series
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: MetricSeries].self, from: data) else { return }
        series = decoded
        // Whatever was accumulating when the app quit is stale: flush it as its own point.
        for k in series.keys { for i in series[k]!.tiers.indices { series[k]!.tiers[i].flush() } }
    }
}

/// Average down to at most `maxPoints` so Swift Charts stays responsive.
func downsample(_ pts: [HPoint], maxPoints: Int) -> [HPoint] {
    guard pts.count > maxPoints, maxPoints > 0 else { return pts }
    let step = Int((Double(pts.count) / Double(maxPoints)).rounded(.up))
    var out: [HPoint] = []
    out.reserveCapacity(pts.count / step + 1)
    var i = 0
    while i < pts.count {
        let chunk = pts[i..<min(i + step, pts.count)]
        let n = Double(chunk.count)
        out.append(HPoint(t: chunk.reduce(0) { $0 + $1.t } / n, v: chunk.reduce(0) { $0 + $1.v } / n))
        i += step
    }
    return out
}

/// Split a series where consecutive samples are further apart than `gap` seconds (sleep, app not running).
func segments(_ pts: [HPoint], gap: Double) -> [[HPoint]] {
    var out: [[HPoint]] = []
    var cur: [HPoint] = []
    for p in pts {
        if let last = cur.last, p.t - last.t > gap { out.append(cur); cur = [] }
        cur.append(p)
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}
