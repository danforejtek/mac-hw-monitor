import Foundation
import SwiftUI
import Combine

struct Snapshot {
    var cpu = CPUSample()
    var gpu = GPUSample()
    var memory = MemorySample()
    var disk = DiskSample()
    var network = NetworkSample()
    var thermal: ProcessInfo.ThermalState = .nominal
    var timestamp = Date()
}

/// Owns the samplers, drives the refresh loop, feeds the history store and renders the
/// menu bar images. Chart data is published only while some panel is visible.
@MainActor
final class Monitor: ObservableObject {
    static let shared = Monitor()

    let system = SystemInfo.collect()
    let history = HistoryStore()

    private(set) var snapshot = Snapshot()
    private(set) var topByCPU: [ProcessSample] = []
    private(set) var topByMemory: [ProcessSample] = []
    private(set) var ollama = OllamaStatus()
    @Published private(set) var menuImages: [Metric: NSImage] = [:]
    @Published private(set) var combinedImage: NSImage?
    /// Metric shown in the history window.
    @Published var historyMetric: Metric = .cpu

    /// Number of open dropdowns / windows that display chart data.
    private var visiblePanels = 0
    var chartsVisible: Bool { visiblePanels > 0 }
    func panelAppeared() { visiblePanels += 1; objectWillChange.send() }
    func panelDisappeared() { visiblePanels = max(0, visiblePanels - 1) }

    /// Only one dropdown at a time: opening one closes the others, as iStat Menus does.
    private var dropdownWindows: [Metric: NSWindow] = [:]
    func dropdownOpened(_ metric: Metric, window: NSWindow) {
        if dropdownWindows[metric] === window { return }
        dropdownWindows[metric] = window
        for (m, w) in dropdownWindows where m != metric && w.isVisible { w.close() }
    }
    func dropdownClosed(_ metric: Metric) { dropdownWindows[metric] = nil }

    private let cpuSampler = CPUSampler()
    private let gpuSampler = GPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()
    private let networkSampler = NetworkSampler()
    private let processSampler = ProcessSampler()
    private let ollamaClient = OllamaClient()
    private var loop: Task<Void, Never>?
    private var tick = 0

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.history.save()
        }
        start()
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            _ = self?.cpuSampler.sample(); _ = self?.diskSampler.sample(); _ = self?.networkSampler.sample()
            _ = self?.memorySampler.sample(); _ = self?.processSampler.sample()
            while !Task.isCancelled {
                let interval = max(0.5, UserDefaults.standard.double(forKey: SettingsKey.refreshInterval))
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func refresh() async {
        let cpuS = cpuSampler, gpuS = gpuSampler, memS = memorySampler, diskS = diskSampler, netS = networkSampler
        var snap = await Task.detached(priority: .utility) {
            var s = Snapshot()
            s.cpu = cpuS.sample()
            s.gpu = gpuS.sample()
            s.memory = memS.sample()
            s.disk = diskS.sample()
            s.network = netS.sample()
            return s
        }.value
        snap.thermal = ProcessInfo.processInfo.thermalState
        snap.timestamp = Date()
        if chartsVisible { objectWillChange.send() }
        snapshot = snap

        let now = snap.timestamp
        history.add(.cpuUser, snap.cpu.user, at: now)
        history.add(.cpuSystem, snap.cpu.system, at: now)
        history.add(.gpu, snap.gpu.device, at: now)
        history.add(.memUsed, snap.memory.usedPercent, at: now)
        history.add(.memPressure, snap.memory.pressurePercent, at: now)
        history.add(.diskRead, snap.disk.readPerSec, at: now)
        history.add(.diskWrite, snap.disk.writePerSec, at: now)
        history.add(.netIn, snap.network.inPerSec, at: now)
        history.add(.netOut, snap.network.outPerSec, at: now)
        history.add(.load1, snap.cpu.loadAverage.0, at: now)
        history.add(.load5, snap.cpu.loadAverage.1, at: now)
        history.add(.load15, snap.cpu.loadAverage.2, at: now)
        history.saveIfDue()

        tick += 1
        if tick % 2 == 0 {
            let ps = processSampler
            let (c, m) = await Task.detached(priority: .utility) { ps.sample(limit: 6) }.value
            if chartsVisible { objectWillChange.send() }
            topByCPU = c; topByMemory = m
        }
        if tick % 5 == 1 {
            let url = UserDefaults.standard.string(forKey: SettingsKey.ollamaURL) ?? "http://127.0.0.1:11434"
            let status = await ollamaClient.fetch(baseURL: url)
            if chartsVisible { objectWillChange.send() }
            ollama = status
        }
        renderMenuBarImages()
    }

    func refreshOllamaNow() {
        Task { [weak self] in
            guard let self else { return }
            let url = UserDefaults.standard.string(forKey: SettingsKey.ollamaURL) ?? "http://127.0.0.1:11434"
            let status = await self.ollamaClient.fetch(baseURL: url)
            self.objectWillChange.send()
            self.ollama = status
        }
    }

    // MARK: - Menu bar

    private func renderMenuBarImages() {
        let d = UserDefaults.standard
        let graphs = d.bool(forKey: SettingsKey.menuGraphs)
        let labels = d.bool(forKey: SettingsKey.menuLabels)
        func pct(_ key: HistoryStore.Key) -> [Double] { history.recent(key, seconds: 40).map { $0.v / 100 } }
        func scaled(_ key: HistoryStore.Key) -> [Double] {
            let v = history.recent(key, seconds: 40).map { $0.v }
            let m = max(v.max() ?? 0, 1)
            return v.map { $0 / m }
        }
        let segments: [Metric: MenuBarImage.Segment] = [
            .cpu: .init(title: "CPU", value: String(format: "%.0f%%", snapshot.cpu.total),
                        series: [(pct(.cpuUser), .systemBlue), (pct(.cpuSystem), .systemRed)], stacked: true),
            .gpu: .init(title: "GPU", value: String(format: "%.0f%%", snapshot.gpu.device), series: [(pct(.gpu), .systemGreen)]),
            .memory: .init(title: "MEM", value: String(format: "%.0f%%", snapshot.memory.usedPercent), series: [(pct(.memUsed), .systemPurple)]),
            .disk: .init(title: "DISK", lines: ["R " + Fmt.rate(snapshot.disk.readPerSec), "W " + Fmt.rate(snapshot.disk.writePerSec)],
                         series: [(scaled(.diskRead), .systemCyan), (scaled(.diskWrite), .systemOrange)]),
            .network: .init(title: "NET", lines: ["\u{2193} " + Fmt.rate(snapshot.network.inPerSec), "\u{2191} " + Fmt.rate(snapshot.network.outPerSec)],
                            series: [(scaled(.netIn), .systemMint), (scaled(.netOut), .systemPink)]),
        ]
        var images: [Metric: NSImage] = [:]
        for (metric, seg) in segments { images[metric] = MenuBarImage.make([seg], graphs: graphs, labels: labels) }
        menuImages = images
        if d.bool(forKey: SettingsKey.menuCombined) {
            let enabled = Metric.allCases.filter(\.enabled).compactMap { segments[$0] }
            combinedImage = MenuBarImage.make(enabled, graphs: graphs, labels: labels)
        }
    }
}
