# macos-monitor

Lightweight macOS menu bar monitor. Native Swift, zero dependencies.

## Features

- **Local tab** — CPU / memory / GPU / network, EMA-smoothed
- **Remote tab** — same metrics from a Linux VPS over SSH (see below)
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

## Remote monitoring (VPS)

The Remote tab talks to a tiny Go agent you deploy on the VPS. No ports are opened — everything rides on a single SSH connection.

### 1. Build the agent

```sh
cd agent
./build.sh              # produces linux/amd64 and linux/arm64 binaries
```

Or grab the pre-built binary from the [latest release](https://github.com/andy00614/macos-monitor/releases).

### 2. Deploy to your VPS

```sh
# pick the binary matching your VPS architecture (uname -m on the VPS)
scp agent/macos-monitor-agent-linux-amd64 user@host:~/macos-monitor-agent
ssh user@host 'chmod +x ~/macos-monitor-agent'
```

Prerequisites on the VPS: Linux with `/proc` (any modern distro); no other dependencies — the binary is statically linked.

### 3. Connect from the app

Open the popover → **Remote** tab → paste `user@host` (or an `~/.ssh/config` alias) → **Connect**. The host is saved to `UserDefaults`, so the next launch auto-reconnects.

### How it works

```
 macOS App  ──┐                     ┌── VPS
              │                     │
              │   ssh user@host     │
              │   ./macos-monitor-  │
              │   agent -interval 2 │
              │                     │
   NSProcess ─┼──── stdin pipe ─────┼─► agent (keeps agent alive)
              │                     │
   readJSON ◄─┼─── stdout stream ───┼─  agent prints snapshot every 2s
              │                     │      (reads /proc/stat, meminfo, net/dev)
              └─────────────────────┘
```

One persistent SSH connection. ~200 B per snapshot (~100 B/s bandwidth). End-to-end latency = network RTT. No new ports on the VPS. Auth is your existing SSH key.

## Architecture

Local samplers read kernel data every 2 s:

| Source                                    | Metric         |
| ----------------------------------------- | -------------- |
| `host_processor_info` (Mach)              | CPU            |
| `host_statistics64` + `sysctl hw.memsize` | Memory         |
| `proc_listpids` / `proc_pidinfo` (libproc)| Top processes  |
| `getifaddrs` (BSD)                        | Network        |
| `IOServiceMatching("IOAccelerator")`      | GPU            |

CPU values go through an exponential moving average (α = 0.45) to kill jitter without introducing noticeable lag.

**Menu bar icon** is a SwiftUI view rendered to `NSImage` via `ImageRenderer` on each tick — one SF Symbol (`cpu`, `memorychip`) + mini capsule bar per metric. Three threshold colors (`.systemGreen` < 60%, `.systemOrange` < 85%, `.systemRed` ≥ 85%).

**Popover** is a custom `NSPanel` (`.nonactivatingPanel`, `.popUpMenu` level) positioned manually below the status item. `NSPopover` has a flipped-coord quirk on `NSStatusBarButton` that places the window at screen top on some setups; a panel side-steps it and gives full layout control. Subclassed to override `canBecomeKey` so the text field accepts keyboard input.

## Project layout

```
Sources/MacosMonitor/
├── App.swift                 # @main, AppDelegate, Edit menu setup
├── StatusBarController.swift # panel + timer + orchestration
├── SystemMetrics.swift       # Mach
├── ProcessSampler.swift      # libproc
├── NetworkSampler.swift      # getifaddrs
├── GPUSampler.swift          # IOKit
├── LoginItemService.swift    # SMAppService
├── RemoteSampler.swift       # spawns ssh, reads JSON stream
├── DebugLog.swift            # /tmp/macosmonitor.log
└── MenuView.swift            # SwiftUI views
agent/
├── main.go                   # Linux agent: reads /proc, streams JSON
└── build.sh                  # cross-compile for linux/amd64 + arm64
tools/
├── generate_icon.swift       # .icns generator
└── package_dmg.sh            # hdiutil wrapper
run.sh                        # build + relaunch
```

## Caveats

- GPU row is hidden automatically if `IOAccelerator.PerformanceStatistics` doesn't expose utilization.
- Unsigned build — fine for personal use, needs Developer ID + notarization for friction-free distribution.
- Launch-at-login registers the `.app` at its current path; if you move the bundle, toggle off then back on.
- Remote auth requires working passwordless SSH (public key). BatchMode is enforced so the app never prompts for a password.
