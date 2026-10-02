import Foundation
import IOKit

struct GPUSample {
    var available = false
    var device: Double = 0     // "Device Utilization %"
    var renderer: Double = 0
    var tiler: Double = 0
    var memoryInUse: UInt64 = 0
    var memoryAllocated: UInt64 = 0
}

/// GPU utilization from the IOAccelerator PerformanceStatistics dictionary (works unprivileged on Apple Silicon).
final class GPUSampler {
    func sample() -> GPUSample {
        var out = GPUSample()
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            guard let props = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }
            func num(_ k: String) -> Double? { (props[k] as? NSNumber)?.doubleValue }
            guard let dev = num("Device Utilization %") else { continue }
            out.available = true
            out.device = max(out.device, dev)
            out.renderer = max(out.renderer, num("Renderer Utilization %") ?? 0)
            out.tiler = max(out.tiler, num("Tiler Utilization %") ?? 0)
            out.memoryInUse += UInt64(num("In use system memory") ?? 0)
            out.memoryAllocated += UInt64(num("Alloc system memory") ?? 0)
        }
        return out
    }
}
