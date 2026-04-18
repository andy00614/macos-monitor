# macos-monitor

Lightweight macOS menu bar monitor. Native Swift, zero dependencies.

## Features

- CPU / memory / GPU / network — live, EMA-smoothed
- Top 3 processes by CPU
- Launch at login (`SMAppService`)
- ~0.1% CPU, ~15 MB RSS while running

## Build & run

```sh
./run.sh
```

Requires macOS 13+ and Xcode Command Line Tools. First run generates the `.icns` icon, builds the release binary, and launches `MacosMonitor.app`.

## Distribute

```sh
./tools/package_dmg.sh
```

Produces `MacosMonitor.dmg` (~900 KB, unsigned). Recipients need to right-click → Open, or `xattr -dr com.apple.quarantine MacosMonitor.app` to clear Gatekeeper quarantine.

## Architecture

Samplers read kernel data every 2 s:

| Source                                    | Metric         |
| ----------------------------------------- | -------------- |
| `host_processor_info` (Mach)              | CPU            |
| `host_statistics64` + `sysctl hw.memsize` | Memory         |
| `proc_listpids` / `proc_pidinfo` (libproc)| Top processes  |
| `getifaddrs` (BSD)                        | Network        |
| `IOServiceMatching("IOAccelerator")`      | GPU            |

CPU values go through an exponential moving average (α = 0.45) to kill jitter without introducing noticeable lag.

**Menu bar icon** is a SwiftUI view rendered to `NSImage` via `ImageRenderer` on each tick — one SF Symbol (`cpu`, `memorychip`) + mini capsule bar per metric. Three threshold colors (`.systemGreen` < 60%, `.systemOrange` < 85%, `.systemRed` ≥ 85%).

**Popover** is a custom `NSPanel` (`.nonactivatingPanel`, `.popUpMenu` level) positioned manually below the status item. `NSPopover` has a flipped-coord quirk on `NSStatusBarButton` that places the window at screen top on some setups; a panel side-steps it and gives full layout control.

## Project layout

```
Sources/MacosMonitor/
├── App.swift                 # @main, AppDelegate
├── StatusBarController.swift # panel + timer + orchestration
├── SystemMetrics.swift       # Mach
├── ProcessSampler.swift      # libproc
├── NetworkSampler.swift      # getifaddrs
├── GPUSampler.swift          # IOKit
├── LoginItemService.swift    # SMAppService
└── MenuView.swift            # SwiftUI views (popover + menu bar icon)
tools/
├── generate_icon.swift       # .icns generator (CPU SF Symbol on green squircle)
└── package_dmg.sh            # hdiutil wrapper
run.sh                        # build + relaunch
```

## Caveats

- GPU row is hidden automatically if `IOAccelerator.PerformanceStatistics` doesn't expose utilization (some Intel Macs, some VM setups).
- Unsigned build — fine for personal use, needs Developer ID + notarization for friction-free distribution.
- Launch-at-login registers the `.app` at its current path; if you move the bundle, toggle off then back on.
