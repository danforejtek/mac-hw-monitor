import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @AppStorage(SettingsKey.showCPU) private var showCPU = true
    @AppStorage(SettingsKey.showGPU) private var showGPU = true
    @AppStorage(SettingsKey.showMemory) private var showMemory = true
    @AppStorage(SettingsKey.showDisk) private var showDisk = false
    @AppStorage(SettingsKey.showNetwork) private var showNetwork = true
    @AppStorage(SettingsKey.menuGraphs) private var menuGraphs = true
    @AppStorage(SettingsKey.menuLabels) private var menuLabels = true
    @AppStorage(SettingsKey.menuGraphWidth) private var graphWidth = 32.0
    @AppStorage(SettingsKey.ollamaURL) private var ollamaURL = "http://127.0.0.1:11434"
    @StateObject private var launchAtLogin = UIState(SMAppService.mainApp.status == .enabled)
    @StateObject private var loginError = UIState<String?>(nil)

    var body: some View {
        Form {
            Section("Sampling") {
                Picker("Refresh every", selection: $interval) {
                    Text("0.5 s").tag(0.5); Text("1 s").tag(1.0); Text("2 s").tag(2.0); Text("5 s").tag(5.0)
                }
            }
            Section("Menu bar items") {
                Toggle("CPU", isOn: $showCPU)
                Toggle("GPU", isOn: $showGPU)
                Toggle("Memory", isOn: $showMemory)
                Toggle("Disk", isOn: $showDisk)
                Toggle("Network", isOn: $showNetwork)
                Toggle("Show graphs", isOn: $menuGraphs)
                Toggle("Show labels and values", isOn: $menuLabels)
                HStack {
                    Text("Graph width")
                    Slider(value: $graphWidth, in: 16...80, step: 4)
                    Text("\(Int(graphWidth)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                }
                .disabled(!menuGraphs)
                Text("macOS hides status items that don't fit beside the active app's menus. Narrower items or fewer of them help.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local LLM") {
                TextField("Ollama URL", text: $ollamaURL)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin.value)
                    .onChange(of: launchAtLogin.value) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError.value = nil
                        } catch {
                            loginError.value = error.localizedDescription
                            launchAtLogin.value = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let e = loginError.value { Text(e).font(.caption).foregroundStyle(.red) }
                Text("History is kept for 30 days in ~/Library/Application Support/HWMonitor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 540)
    }
}
