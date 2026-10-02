import Foundation

enum SettingsKey {
    static let refreshInterval = "refreshInterval"      // seconds
    static let showCPU = "menuShowCPU"
    static let showGPU = "menuShowGPU"
    static let showMemory = "menuShowMemory"
    static let showDisk = "menuShowDisk"
    static let showNetwork = "menuShowNetwork"
    static let menuGraphs = "menuGraphs"
    static let menuLabels = "menuLabels"
    static let menuGraphWidth = "menuGraphWidth"      // points
    static let menuCombined = "menuCombined"          // one status item for all metrics
    static let combinedMetric = "combinedMetric"      // tab selected in the combined dropdown
    static let ollamaURL = "ollamaURL"
    static let historyRange = "historyRange"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            refreshInterval: 1.0,
            showCPU: true,
            showGPU: true,
            showMemory: true,
            showDisk: false,
            showNetwork: true,
            menuGraphs: true,
            menuLabels: true,
            menuGraphWidth: 32.0,
            menuCombined: false,
            combinedMetric: Metric.cpu.rawValue,
            ollamaURL: "http://127.0.0.1:11434",
            historyRange: HistoryRange.hour.rawValue,
        ])
    }
}

/// The metrics that get their own menu bar item / dropdown / history chart.
enum Metric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, disk, network
    var id: String { rawValue }
    var title: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "Memory"; case .disk: "Disk"; case .network: "Network" }
    }
    /// Whether the user enabled this metric's menu bar item.
    var enabled: Bool {
        let d = UserDefaults.standard
        switch self {
        case .cpu: return d.bool(forKey: SettingsKey.showCPU)
        case .gpu: return d.bool(forKey: SettingsKey.showGPU)
        case .memory: return d.bool(forKey: SettingsKey.showMemory)
        case .disk: return d.bool(forKey: SettingsKey.showDisk)
        case .network: return d.bool(forKey: SettingsKey.showNetwork)
        }
    }
    var symbol: String {
        switch self { case .cpu: "cpu"; case .gpu: "rectangle.3.group"; case .memory: "memorychip"; case .disk: "internaldrive"; case .network: "network" }
    }
}
