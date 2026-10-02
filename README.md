# HW Monitor

A small macOS menu bar app in the spirit of iStat Menus, built to watch the hardware while a
local LLM (Ollama) is running. Native SwiftUI + AppKit, no third-party dependencies, no root,
no Xcode required (builds with the Command Line Tools).

## What it shows

Like iStat Menus, every metric is its own menu bar item with its own dropdown. The menu bar shows a
40-second sparkline plus label/value for each enabled item (CPU, GPU, Memory, Disk, Network).

| Dropdown | Sections |
|---|---|
| CPU | Stacked user/system chart with per-core bars, user/system/idle, P- and E-cluster bars, top processes with icons, chip summary (memory / processor / GPU meters, thermal state), load average chart with peak, uptime |
| GPU | Utilization chart, device/renderer/tiler, GPU memory in use vs allocated, Ollama section (version, loaded models, size, % resident on GPU, quantization, unload time, ollama process), GPU core count |
| Memory | Pressure bar with app/wired/compressed/cache, used-memory chart, wired/active/compressed/free stacked bar, top processes by footprint, swap, page ins/outs |
| Disk | Read/write throughput chart, totals since boot, every mounted volume with usage bar |
| Network | Download/upload chart, totals since boot, interfaces with IPv4 address and per-interface rates |

Clicking a chart (or the chart button in the footer) opens the **History** window with
**1 Hour / 24 Hours / 7 Days / 30 Days** tabs for any metric. History is kept in four tiers
(1 s / 1 min / 10 min / 1 h averages) and persisted to `~/Library/Application Support/HWMonitor/history.json`
every minute and on quit, so the longer ranges survive restarts. Gaps (sleep, app not running) are left blank.

The footer of each dropdown also has Activity Monitor, Settings (refresh interval, which items to show,
graphs/labels, Ollama URL, launch at login) and Quit.

Data sources: `host_processor_info`, `host_statistics64`, `vm.swapusage`, `kern.memorystatus_level`,
IOAccelerator `PerformanceStatistics`, IOBlockStorageDriver `Statistics`, `statfs`, `getifaddrs`,
libproc `proc_pid_rusage`, and Ollama's `/api/version` + `/api/ps`.

## Build and run

```bash
./build.sh --run
```

`build.sh` runs `swift build -c release`, assembles `build/HWMonitor.app` (with `LSUIElement` so
there is no Dock icon), ad-hoc signs it and, with `--run`, launches it. `--install` copies the
bundle to `/Applications` (or `~/Applications` if that is not writable) and relaunches it from there.

Launch at login can be toggled in Settings or from the terminal (the app must run from its installed location):

```bash
/Applications/HWMonitor.app/Contents/MacOS/HWMonitor --enable-launch-at-login
/Applications/HWMonitor.app/Contents/MacOS/HWMonitor --disable-launch-at-login
/Applications/HWMonitor.app/Contents/MacOS/HWMonitor --login-status
```

Requirements: macOS 14+, Swift 5.9+ toolchain (tested with Command Line Tools 26 / Swift 6.4 on an M3 Max).

## Notes

- The Command Line Tools toolchain cannot expand the `@State` macro from the macOS 26 SDK
  (`SwiftUIMacros` plugin is missing). The code uses `@StateObject` with a tiny `UIState<T>` box
  instead; see `Sources/HWMonitor/Util/UIState.swift`. With full Xcode you could switch back to `@State`.
- Idle cost is about 3–4% of one core and ~25 MB. Chart data is collected continuously but only
  published to SwiftUI while a dropdown or the history window is open.
- GPU figures come from the same IORegistry counters Activity Monitor uses. On Apple Silicon the GPU
  shares unified memory, so a loaded model shows up both as GPU memory and in the memory section.
- Temperatures and power (SMC sensors) are not included yet; `ProcessInfo.thermalState` is shown instead.

## License

MIT, see `LICENSE`.
