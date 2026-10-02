import SwiftUI
import ServiceManagement

/// Keeps the app alive when its last window (a dropdown or the history window) closes.
/// SwiftUI otherwise terminates an app that declares a `Window` scene once no window is open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
}

@main
struct HWMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: Monitor
    @AppStorage(SettingsKey.showCPU) private var showCPU = true
    @AppStorage(SettingsKey.showGPU) private var showGPU = true
    @AppStorage(SettingsKey.showMemory) private var showMemory = true
    @AppStorage(SettingsKey.showDisk) private var showDisk = false
    @AppStorage(SettingsKey.showNetwork) private var showNetwork = true

    init() {
        Self.handleCommandLine()
        SettingsKey.registerDefaults()
        _monitor = StateObject(wrappedValue: Monitor.shared)
    }

    var body: some Scene {
        // Scenes are added to the menu bar right-to-left in declaration order, so CPU ends up leftmost.
        MenuBarExtra(isInserted: $showNetwork) { NetworkDropdown(monitor: monitor) } label: { label(.network) }
            .menuBarExtraStyle(.window)
        MenuBarExtra(isInserted: $showDisk) { DiskDropdown(monitor: monitor) } label: { label(.disk) }
            .menuBarExtraStyle(.window)
        MenuBarExtra(isInserted: $showMemory) { MemoryDropdown(monitor: monitor) } label: { label(.memory) }
            .menuBarExtraStyle(.window)
        MenuBarExtra(isInserted: $showGPU) { GPUDropdown(monitor: monitor) } label: { label(.gpu) }
            .menuBarExtraStyle(.window)
        MenuBarExtra(isInserted: $showCPU) { CPUDropdown(monitor: monitor) } label: { label(.cpu) }
            .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryWindow(monitor: monitor)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView()
        }
    }

    /// `--enable-launch-at-login`, `--disable-launch-at-login`, `--login-status`: act and exit.
    private static func handleCommandLine() {
        let args = CommandLine.arguments.dropFirst()
        guard let flag = args.first(where: { $0.hasPrefix("--") }) else { return }
        let service = SMAppService.mainApp
        func describe(_ s: SMAppService.Status) -> String {
            switch s {
            case .enabled: "enabled"
            case .notRegistered: "not registered"
            case .requiresApproval: "requires approval in System Settings > Login Items"
            case .notFound: "not found"
            @unknown default: "unknown"
            }
        }
        do {
            switch flag {
            case "--enable-launch-at-login": try service.register()
            case "--disable-launch-at-login": try service.unregister()
            case "--login-status": break
            default: print("unknown option \(flag)"); exit(2)
            }
            print("launch at login: \(describe(service.status))")
            exit(0)
        } catch {
            print("failed: \(error.localizedDescription) (status: \(describe(service.status)))")
            exit(1)
        }
    }

    @ViewBuilder
    private func label(_ metric: Metric) -> some View {
        if let img = monitor.menuImages[metric] {
            Image(nsImage: img)
        } else {
            Image(systemName: metric.symbol)
        }
    }
}
