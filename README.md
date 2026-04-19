# Orbit

Menu bar monitor for your Mac + any Linux VPS. Native Swift, zero dependencies, ~0.1% CPU.

## Install

Paste into Terminal:

```sh
curl -L -o /tmp/Orbit.dmg https://github.com/andy00614/orbit/releases/latest/download/Orbit.dmg
hdiutil attach -nobrowse /tmp/Orbit.dmg
cp -R "/Volumes/Orbit/Orbit.app" /Applications/
hdiutil detach "/Volumes/Orbit"
xattr -dr com.apple.quarantine /Applications/Orbit.app
open /Applications/Orbit.app
```

Click the menu bar icon → you should see local CPU / memory / GPU / network bars + top processes.

## Add a remote VPS (optional)

**On the VPS**, drop in the agent binary (pick the arch matching `uname -m`):

```sh
# x86_64:
curl -L -o ~/orbit-agent https://github.com/andy00614/orbit/releases/latest/download/orbit-agent-linux-amd64
# aarch64:
curl -L -o ~/orbit-agent https://github.com/andy00614/orbit/releases/latest/download/orbit-agent-linux-arm64

chmod +x ~/orbit-agent
```

No daemon, no port, no dependencies — it's a single static binary that runs only while the Mac app is connected.

**On the Mac**, click the menu bar icon → Remote section → paste `user@host` → Connect.

Requires passwordless SSH (your public key already in VPS `~/.ssh/authorized_keys`).

## Build from source

```sh
git clone https://github.com/andy00614/orbit
cd orbit
./run.sh
```

Requires macOS 13+ and Xcode Command Line Tools.

## How it works

- **Local**: `host_processor_info`, `host_statistics64`, `proc_listpids`, `getifaddrs`, `IOAccelerator` every 2 s
- **Remote**: one persistent SSH connection runs the Go agent on the VPS, which reads `/proc` and streams JSON to stdout (~100 B/s, latency = network RTT)
- **Menu bar icon**: SwiftUI view rendered to `NSImage` on each tick; local bars | server glyph + remote bars
- **Popover**: custom `NSPanel` (sidesteps `NSPopover`'s flipped-coord quirk on menu bar buttons)

## Caveats

- Unsigned build — the `xattr` line in the install block clears Gatekeeper quarantine.
- GPU row hidden when `IOAccelerator.PerformanceStatistics` doesn't expose utilization (some Intel Macs, VMs).
- Launch-at-login binds to the `.app` path; if you move it, toggle off/on.
