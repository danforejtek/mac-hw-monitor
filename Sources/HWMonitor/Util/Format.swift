import Foundation

enum Fmt {
    static func bytes(_ v: Double, decimals: Int = 1) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = v
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.\(decimals)f %@", value, units[i])
    }
    static func bytes(_ v: UInt64, decimals: Int = 1) -> String { bytes(Double(v), decimals: decimals) }

    static func rate(_ bytesPerSec: Double) -> String { bytes(bytesPerSec) + "/s" }

    static func percent(_ v: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", v)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
