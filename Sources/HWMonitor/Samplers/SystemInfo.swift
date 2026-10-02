import Foundation
import IOKit

enum Sysctl {
    static func string(_ name: String) -> String? {
        var len = 0
        guard sysctlbyname(name, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: len)
        guard sysctlbyname(name, &buf, &len, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    static func int<T: FixedWidthInteger>(_ name: String, as: T.Type = T.self) -> T? {
        var v: T = 0
        var len = MemoryLayout<T>.size
        guard sysctlbyname(name, &v, &len, nil, 0) == 0 else { return nil }
        return v
    }
}

struct SystemInfo {
    let chip: String
    let logicalCPUs: Int
    let performanceCores: Int
    let efficiencyCores: Int
    /// Index of the first performance core, assuming efficiency cores are numbered first (Apple Silicon layout).
    var firstPerformanceCore: Int { efficiencyCores }
    let totalMemory: UInt64
    let gpuCores: Int?
    let bootTime: Date
    let osVersion: String

    static func collect() -> SystemInfo {
        let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"
        let ncpu = Int(Sysctl.int("hw.ncpu", as: Int32.self) ?? 0)
        var p = 0, e = 0
        if let n0 = Sysctl.int("hw.perflevel0.logicalcpu", as: Int32.self) {
            let name0 = Sysctl.string("hw.perflevel0.name") ?? "Performance"
            let n1 = Sysctl.int("hw.perflevel1.logicalcpu", as: Int32.self) ?? 0
            if name0.lowercased().hasPrefix("perf") { p = Int(n0); e = Int(n1) } else { e = Int(n0); p = Int(n1) }
        } else {
            p = ncpu
        }
        let mem = Sysctl.int("hw.memsize", as: UInt64.self) ?? 0

        var bt = timeval()
        var len = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &bt, &len, nil, 0)
        let boot = Date(timeIntervalSince1970: TimeInterval(bt.tv_sec))

        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")

        return SystemInfo(chip: chip, logicalCPUs: ncpu, performanceCores: p, efficiencyCores: e,
                          totalMemory: mem, gpuCores: gpuCoreCount(), bootTime: boot, osVersion: os)
    }

    private static func gpuCoreCount() -> Int? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            let opts = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            if let n = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, "gpu-core-count" as CFString, kCFAllocatorDefault, opts) as? Int {
                return n
            }
        }
        return nil
    }
}
