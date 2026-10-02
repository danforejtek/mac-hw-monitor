import Foundation
import Darwin

enum MemoryPressure: String { case normal = "Normal", warning = "Warning", critical = "Critical" }

struct MemorySample {
    var total: UInt64 = 0
    var used: UInt64 = 0         // app + wired + compressed (Activity Monitor "Memory Used")
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0       // file-backed pages
    var free: UInt64 = 0         // free + speculative
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var pageInsPerSec: Double = 0   // bytes/s
    var pageOutsPerSec: Double = 0
    var pressurePercent: Double = 0 // 100 - kern.memorystatus_level
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal
    var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    var available: UInt64 { total > used ? total - used : 0 }
}

final class MemorySampler {
    private let total: UInt64 = Sysctl.int("hw.memsize", as: UInt64.self) ?? 0
    private var lastPageIns: UInt64 = 0, lastPageOuts: UInt64 = 0
    private var lastTime: Date?
    private let pageSize: UInt64 = {
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        return UInt64(ps)
    }()

    func sample() -> MemorySample {
        var s = MemorySample()
        s.total = total

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let ps = pageSize
            s.wired = UInt64(stats.wire_count) * ps
            s.compressed = UInt64(stats.compressor_page_count) * ps
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * ps
            s.cached = UInt64(stats.external_page_count) * ps
            s.free = (UInt64(stats.free_count) + UInt64(stats.speculative_count)) * ps
            s.active = UInt64(stats.active_count) * ps
            s.inactive = UInt64(stats.inactive_count) * ps
            s.used = s.app + s.wired + s.compressed

            let now = Date()
            let ins = UInt64(stats.pageins), outs = UInt64(stats.pageouts)
            if let t = lastTime {
                let dt = now.timeIntervalSince(t)
                if dt > 0 {
                    s.pageInsPerSec = ins >= lastPageIns ? Double((ins - lastPageIns) * ps) / dt : 0
                    s.pageOutsPerSec = outs >= lastPageOuts ? Double((outs - lastPageOuts) * ps) / dt : 0
                }
            }
            lastPageIns = ins; lastPageOuts = outs; lastTime = now
        }
        if let level: Int32 = Sysctl.int("kern.memorystatus_level") {
            s.pressurePercent = Double(max(0, min(100, 100 - Int(level))))
        }

        var sw = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &sw, &len, nil, 0) == 0 {
            s.swapUsed = sw.xsu_used
            s.swapTotal = sw.xsu_total
        }

        if let lvl: Int32 = Sysctl.int("kern.memorystatus_vm_pressure_level") {
            switch lvl {
            case 4: s.pressure = .critical
            case 2: s.pressure = .warning
            default: s.pressure = .normal
            }
        }
        return s
    }
}
