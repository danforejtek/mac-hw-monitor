import Foundation
import Darwin

struct ProcessSample: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let path: String
    let cpuPercent: Double      // 100 = one full core
    let memory: UInt64          // physical footprint (Activity Monitor "Memory")
    var id: pid_t { pid }
}

/// Per-process CPU and memory via libproc. No privileges needed for the user's own and most system processes.
final class ProcessSampler {
    private var lastCPUTime: [pid_t: UInt64] = [:]   // nanoseconds
    private var lastTime: Date?
    private var names: [pid_t: (name: String, path: String)] = [:]
    private let timebase: Double = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    func sample(limit: Int = 8) -> (byCPU: [ProcessSample], byMemory: [ProcessSample]) {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return ([], []) }
        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<pid_t>.size + 32)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(got) / MemoryLayout<pid_t>.size

        let now = Date()
        let dt = lastTime.map { now.timeIntervalSince($0) } ?? 0
        var current: [pid_t: UInt64] = [:]
        var samples: [ProcessSample] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var ru = rusage_info_current()
            let rc = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard rc == 0 else { continue }
            let cpuNs = UInt64(Double(ru.ri_user_time &+ ru.ri_system_time) * timebase)
            current[pid] = cpuNs
            var cpu = 0.0
            if dt > 0, let prev = lastCPUTime[pid], cpuNs >= prev {
                cpu = Double(cpuNs - prev) / (dt * 1e9) * 100
            }
            let info: (name: String, path: String)
            if let cached = names[pid] { info = cached } else { info = Self.identify(pid); names[pid] = info }
            samples.append(ProcessSample(pid: pid, name: info.name, path: info.path, cpuPercent: cpu, memory: ru.ri_phys_footprint))
        }
        lastCPUTime = current
        lastTime = now
        names = names.filter { current[$0.key] != nil }   // drop exited pids so reused pids get a fresh name

        let byCPU = Array(samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let byMem = Array(samples.sorted { $0.memory > $1.memory }.prefix(limit))
        return (byCPU, byMem)
    }

    private static func identify(_ pid: pid_t) -> (name: String, path: String) {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var path = ""
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { path = String(cString: buf) }
        var name = ""
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 { name = String(cString: buf) }
        if name.isEmpty { name = (path as NSString).lastPathComponent }
        if name.isEmpty { name = "pid \(pid)" }
        if name.hasPrefix("com.apple.Virtualization") {
            // A Virtualization.framework VM (Docker Desktop, OrbStack, UTM, ...): name it after its owner.
            var info = proc_bsdinfo()
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0, info.pbi_ppid > 1 {
                let parent = identify(pid_t(info.pbi_ppid))
                name = "\(parent.name) (VM)"
                if parent.path.contains(".app/") { path = parent.path }
            } else {
                name = "Virtual machine"
            }
        }
        return (name, path)
    }
}
