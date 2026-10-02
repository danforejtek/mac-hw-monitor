import SwiftUI

// MARK: - CPU

struct CPUDropdown: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        let cpu = monitor.snapshot.cpu
        let sys = monitor.system
        DropdownShell(monitor: monitor, metric: .cpu) {
            DropdownSection(title: "CPU") {
                HStack(spacing: 6) {
                    RecentChart(monitor: monitor, metric: .cpu,
                                keys: [(.cpuUser, "User", Palette.user), (.cpuSystem, "System", Palette.system)], stacked: true)
                    CoreBars(cores: cpu.perCore).frame(width: 84, height: 80)
                }
                ValueRow(label: "User", value: Fmt.percent(cpu.user), color: Palette.user)
                ValueRow(label: "System", value: Fmt.percent(cpu.system), color: Palette.system)
                ValueRow(label: "Idle", value: Fmt.percent(cpu.idle), color: Palette.cached)
            }
            if sys.efficiencyCores > 0, cpu.perCore.count == sys.logicalCPUs {
                DropdownSection(title: "Clusters") {
                    let e = Array(cpu.perCore.prefix(sys.efficiencyCores))
                    let p = Array(cpu.perCore.dropFirst(sys.efficiencyCores))
                    clusterRow("Performance (\(p.count) cores)", p)
                    clusterRow("Efficiency (\(e.count) cores)", e)
                }
            }
            DropdownSection(title: "Processes") {
                ForEach(monitor.topByCPU.prefix(5)) { p in
                    ProcessRow(process: p, value: String(format: "%.1f%%", p.cpuPercent))
                }
            }
            DropdownSection(title: "\(sys.chip)") {
                ValueRow(label: "Memory", value: Fmt.percent(monitor.snapshot.memory.usedPercent))
                Meter(fraction: monitor.snapshot.memory.usedPercent / 100, color: Palette.memory)
                ValueRow(label: "Processor", value: Fmt.percent(cpu.total))
                Meter(fraction: cpu.total / 100, color: Palette.user)
                if monitor.snapshot.gpu.available {
                    ValueRow(label: "GPU", value: Fmt.percent(monitor.snapshot.gpu.device))
                    Meter(fraction: monitor.snapshot.gpu.device / 100, color: Palette.gpu)
                }
                ValueRow(label: "Thermal state", value: thermalText(monitor.snapshot.thermal))
            }
            DropdownSection(title: "Load average") {
                RecentChart(monitor: monitor, metric: .cpu,
                            keys: [(.load1, "1 min", Palette.load1), (.load5, "5 min", Palette.load5), (.load15, "15 min", Palette.load15)],
                            maxValue: nil, height: 60, lineOnly: true)
                let peak = monitor.history.recent(.load1, seconds: 180, now: monitor.snapshot.timestamp).map(\.v).max() ?? 0
                Text(String(format: "Peak load: %.2f", peak)).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    legend(Palette.load1, cpu.loadAverage.0); Spacer()
                    legend(Palette.load5, cpu.loadAverage.1); Spacer()
                    legend(Palette.load15, cpu.loadAverage.2)
                }
            }
            DropdownSection(title: "Uptime") {
                Text(uptimeText(sys.bootTime)).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func clusterRow(_ title: String, _ cores: [CoreLoad]) -> some View {
        let avg = cores.isEmpty ? 0 : cores.reduce(0) { $0 + $1.total } / Double(cores.count)
        return HStack(spacing: 10) {
            CoreBars(cores: cores).frame(width: CGFloat(cores.count) * 9, height: 24)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(Fmt.percent(avg)).font(.system(size: 13)).monospacedDigit()
        }
    }

    private func legend(_ color: Color, _ v: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(String(format: "%.2f", v)).font(.system(size: 13)).monospacedDigit()
        }
    }

    private func thermalText(_ s: ProcessInfo.ThermalState) -> String {
        switch s { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; @unknown default: "Unknown" }
    }

    private func uptimeText(_ boot: Date) -> String {
        let s = Int(Date().timeIntervalSince(boot))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d) day\(d == 1 ? "" : "s")") }
        if h > 0 || d > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        parts.append("\(m) minute\(m == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }
}

// MARK: - GPU

struct GPUDropdown: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        let gpu = monitor.snapshot.gpu
        DropdownShell(monitor: monitor, metric: .gpu) {
            DropdownSection(title: "GPU") {
                RecentChart(monitor: monitor, metric: .gpu, keys: [(.gpu, "GPU", Palette.gpu)])
                if gpu.available {
                    ValueRow(label: "Device", value: Fmt.percent(gpu.device), color: Palette.gpu)
                    ValueRow(label: "Renderer", value: Fmt.percent(gpu.renderer))
                    ValueRow(label: "Tiler", value: Fmt.percent(gpu.tiler))
                } else {
                    Text("No IOAccelerator statistics available.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            DropdownSection(title: "GPU memory") {
                Meter(fraction: gpu.memoryAllocated > 0 ? Double(gpu.memoryInUse) / Double(gpu.memoryAllocated) : 0, color: Palette.gpu)
                ValueRow(label: "In use", value: Fmt.bytes(gpu.memoryInUse))
                ValueRow(label: "Allocated", value: Fmt.bytes(gpu.memoryAllocated))
                ValueRow(label: "Unified memory used", value: Fmt.bytes(monitor.snapshot.memory.used) + " / " + Fmt.bytes(monitor.system.totalMemory, decimals: 0), dim: true)
            }
            OllamaSection(monitor: monitor)
            DropdownSection(title: monitor.system.chip) {
                ValueRow(label: "GPU cores", value: monitor.system.gpuCores.map { "\($0)" } ?? "unknown")
                ValueRow(label: "Thermal state", value: "\(monitor.snapshot.thermal == .nominal ? "Nominal" : "Throttling")")
            }
        }
    }
}

struct OllamaSection: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        let o = monitor.ollama
        DropdownSection(title: "Local LLM · Ollama") {
            if o.reachable {
                ValueRow(label: "Server", value: "running" + (o.version.map { " · v\($0)" } ?? ""))
                if o.models.isEmpty {
                    Text("No models loaded.").font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(o.models) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(m.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(Fmt.bytes(m.size)).font(.system(size: 13)).monospacedDigit()
                        }
                        Meter(fraction: m.gpuFraction, color: m.gpuFraction >= 0.999 ? Palette.gpu : .orange)
                        HStack {
                            Text([m.details?.parameter_size, m.details?.quantization_level].compactMap { $0 }.joined(separator: " · "))
                            Spacer()
                            Text(String(format: "%.0f%% on GPU", m.gpuFraction * 100))
                            if let exp = m.expiresAt { Text("· unloads \(Fmt.relative(exp))") }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                let procs = (monitor.topByCPU + monitor.topByMemory).filter { $0.name.lowercased().contains("ollama") }
                if let p = procs.max(by: { $0.memory < $1.memory }) {
                    ProcessRow(process: p, value: String(format: "%.0f%% · %@", p.cpuPercent, Fmt.bytes(p.memory)))
                }
            } else {
                ValueRow(label: "Server", value: o.error ?? "not reachable")
            }
        }
    }
}

// MARK: - Memory

struct MemoryDropdown: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        let m = monitor.snapshot.memory
        DropdownShell(monitor: monitor, metric: .memory) {
            DropdownSection(title: "Pressure") {
                Meter(fraction: m.pressurePercent / 100, color: m.pressure == .normal ? Palette.pressure : m.pressure == .warning ? .yellow : .red)
                ValueRow(label: "Pressure", value: Fmt.percent(m.pressurePercent) + (m.pressure == .normal ? "" : " · \(m.pressure.rawValue)"))
                ValueRow(label: "App Memory", value: Fmt.bytes(m.app, decimals: 2))
                ValueRow(label: "Wired", value: Fmt.bytes(m.wired, decimals: 2))
                ValueRow(label: "Compressed", value: Fmt.bytes(m.compressed, decimals: 2))
                ValueRow(label: "Cache", value: Fmt.bytes(m.cached, decimals: 2))
            }
            DropdownSection(title: "Memory") {
                RecentChart(monitor: monitor, metric: .memory, keys: [(.memUsed, "Used", Palette.memory)], height: 70)
                StackedBar(segments: [(Double(m.wired), Palette.wired), (Double(m.active), Palette.active),
                                      (Double(m.compressed), Palette.compressed)], total: Double(m.total))
                ValueRow(label: "Wired", value: Fmt.bytes(m.wired, decimals: 2), color: Palette.wired)
                ValueRow(label: "Active", value: Fmt.bytes(m.active, decimals: 2), color: Palette.active)
                ValueRow(label: "Compressed", value: Fmt.bytes(m.compressed, decimals: 2), color: Palette.compressed)
                ValueRow(label: "Free", value: Fmt.bytes(m.free, decimals: 2), color: Palette.cached)
                ValueRow(label: "Used (app + wired + compressed)", value: Fmt.bytes(m.used, decimals: 2) + " / " + Fmt.bytes(m.total, decimals: 0), dim: true)
            }
            DropdownSection(title: "Processes") {
                ForEach(monitor.topByMemory.prefix(5)) { p in
                    ProcessRow(process: p, value: Fmt.bytes(p.memory, decimals: p.memory >= 1 << 30 ? 2 : 0))
                }
            }
            DropdownSection(title: "Swap memory") {
                Meter(fraction: m.swapTotal > 0 ? Double(m.swapUsed) / Double(m.swapTotal) : 0, color: Palette.pressure)
                Text(m.swapTotal > 0 ? "\(Fmt.bytes(m.swapUsed, decimals: 2)) of \(Fmt.bytes(m.swapTotal, decimals: 2))" : "No swap in use")
                    .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            }
            DropdownSection(title: "Pages") {
                ValueRow(label: "Page Ins", value: Fmt.rate(m.pageInsPerSec))
                ValueRow(label: "Page Outs", value: Fmt.rate(m.pageOutsPerSec))
            }
        }
    }
}

// MARK: - Disk

struct DiskDropdown: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        let d = monitor.snapshot.disk
        DropdownShell(monitor: monitor, metric: .disk) {
            DropdownSection(title: "Disk activity") {
                RecentChart(monitor: monitor, metric: .disk,
                            keys: [(.diskRead, "Read", Palette.diskRead), (.diskWrite, "Write", Palette.diskWrite)], maxValue: nil)
                ValueRow(label: "Read", value: Fmt.rate(d.readPerSec), color: Palette.diskRead)
                ValueRow(label: "Write", value: Fmt.rate(d.writePerSec), color: Palette.diskWrite)
                ValueRow(label: "Total read since boot", value: Fmt.bytes(d.totalRead), dim: true)
                ValueRow(label: "Total written since boot", value: Fmt.bytes(d.totalWritten), dim: true)
            }
            DropdownSection(title: "Volumes") {
                ForEach(d.volumes) { v in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(v.name).font(.system(size: 13))
                            Spacer()
                            Text("\(Fmt.bytes(v.free)) free of \(Fmt.bytes(v.total, decimals: 0))").font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Meter(fraction: v.usedPercent / 100, color: v.usedPercent > 90 ? .red : Palette.diskRead)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Network

struct NetworkDropdown: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        let n = monitor.snapshot.network
        DropdownShell(monitor: monitor, metric: .network) {
            DropdownSection(title: "Network") {
                RecentChart(monitor: monitor, metric: .network,
                            keys: [(.netIn, "Download", Palette.netIn), (.netOut, "Upload", Palette.netOut)], maxValue: nil)
                ValueRow(label: "Download", value: Fmt.rate(n.inPerSec), color: Palette.netIn)
                ValueRow(label: "Upload", value: Fmt.rate(n.outPerSec), color: Palette.netOut)
                ValueRow(label: "Received since boot", value: Fmt.bytes(n.totalIn), dim: true)
                ValueRow(label: "Sent since boot", value: Fmt.bytes(n.totalOut), dim: true)
            }
            DropdownSection(title: "Interfaces") {
                ForEach(n.interfaces.filter { $0.address != nil || $0.inPerSec + $0.outPerSec > 0 }.prefix(6)) { i in
                    HStack {
                        Text(i.name).font(.system(size: 13, weight: .medium)).frame(width: 48, alignment: .leading)
                        Text(i.address ?? "—").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text("↓ \(Fmt.rate(i.inPerSec))  ↑ \(Fmt.rate(i.outPerSec))").font(.system(size: 12)).monospacedDigit()
                    }
                }
                if n.interfaces.isEmpty {
                    Text("No active interfaces.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
