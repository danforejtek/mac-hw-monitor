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
    var symbol: String {
        switch self { case .cpu: "cpu"; case .gpu: "rectangle.3.group"; case .memory: "memorychip"; case .disk: "internaldrive"; case .network: "network" }
    }
}
