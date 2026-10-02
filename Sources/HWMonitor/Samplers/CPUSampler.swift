import Foundation
import Darwin

struct CoreLoad: Equatable {
    var user: Double = 0, system: Double = 0
    var total: Double { user + system }
}

struct CPUSample {
    var total: Double = 0            // 0...100
    var perCore: [CoreLoad] = []     // 0...100 each
    var user: Double = 0, system: Double = 0, idle: Double = 100
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
}

/// Per-core CPU usage from Mach host_processor_info tick deltas.
final class CPUSampler {
    private struct Ticks { var user = 0.0, system = 0.0, idle = 0.0, nice = 0.0 }
    private var previous: [Ticks] = []

    func sample() -> CPUSample {
        var ncpu: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) == KERN_SUCCESS,
              let info else { return CPUSample() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let n = Int(ncpu)
        let stride = Int(CPU_STATE_MAX)
        var current: [Ticks] = []
        current.reserveCapacity(n)
        for i in 0..<n {
            let base = i * stride
            current.append(Ticks(user: Double(info[base + Int(CPU_STATE_USER)]),
                                 system: Double(info[base + Int(CPU_STATE_SYSTEM)]),
                                 idle: Double(info[base + Int(CPU_STATE_IDLE)]),
                                 nice: Double(info[base + Int(CPU_STATE_NICE)])))
        }

        var out = CPUSample()
        if previous.count == n {
            var perCore: [CoreLoad] = []
            var sumUser = 0.0, sumSys = 0.0, sumIdle = 0.0, sumTotal = 0.0
            for i in 0..<n {
                let du = current[i].user - previous[i].user + current[i].nice - previous[i].nice
                let ds = current[i].system - previous[i].system
                let di = current[i].idle - previous[i].idle
                let dt = du + ds + di
                perCore.append(dt > 0 ? CoreLoad(user: du / dt * 100, system: ds / dt * 100) : CoreLoad())
                sumUser += du; sumSys += ds; sumIdle += di; sumTotal += dt
            }
            out.perCore = perCore
            if sumTotal > 0 {
                out.user = sumUser / sumTotal * 100
                out.system = sumSys / sumTotal * 100
                out.idle = sumIdle / sumTotal * 100
                out.total = out.user + out.system
            }
        } else {
            out.perCore = Array(repeating: CoreLoad(), count: n)
        }
        previous = current

        var la = [Double](repeating: 0, count: 3)
        getloadavg(&la, 3)
        out.loadAverage = (la[0], la[1], la[2])
        return out
    }
}
