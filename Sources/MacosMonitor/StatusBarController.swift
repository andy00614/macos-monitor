import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let sampler = MetricsSampler()
    private let processSampler = ProcessSampler()
    private let networkSampler = NetworkSampler()
    private let gpuSampler = GPUSampler()
    private let model = MetricsModel()
    private let remote = RemoteSampler()
    private var timer: Timer?

    private var panel: NSPanel?
    private var outsideClickMonitor: Any?

    // EMA smoothing coefficient; larger = more responsive, smaller = smoother
    private let cpuAlpha: Double = 0.45
    private var smoothedCPU: Double = 0
    private var smoothedGPU: Double = 0

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "com.macosmonitor.statusbar"

        configureButton()
        startSampling()

        // 保存过 host 就自动连，让 App 启动即有实时远程数据
        if let host = UserDefaults.standard.string(forKey: "remoteHost"), !host.isEmpty {
            remote.connect(host: host)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.image = renderIcon(cpu: 0, memory: 0)
        button.imagePosition = .imageOnly
    }

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let hosting = NSHostingController(rootView: MenuView(model: model, remote: remote))
        hosting.view.layer?.cornerRadius = 12

        let panel = FocusablePanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        // Wrap in a visual-effect "menu" material + rounded clip to match native popover chrome
        let container = NSVisualEffectView()
        container.material = .menu
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container

        // Size to SwiftUI content's fitting size
        let fit = hosting.view.fittingSize
        let size = NSSize(width: max(fit.width, 280), height: max(fit.height, 260))
        panel.setContentSize(size)

        // Position under the menu bar button
        if let button = statusItem.button, let buttonWindow = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            let rectOnScreen = buttonWindow.convertToScreen(rectInWindow)
            let origin = NSPoint(
                x: rectOnScreen.midX - size.width / 2,
                y: rectOnScreen.minY - size.height - 6
            )
            panel.setFrameOrigin(origin)
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Dismiss on any outside click
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Sampling

    private func startSampling() {
        _ = sampler.sample()
        _ = processSampler.sample()
        _ = networkSampler.sample()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let sys = sampler.sample()
        let net = networkSampler.sample()
        let procs = processSampler.sample(top: 3)
        let gpu = gpuSampler.sample()

        smoothedCPU = cpuAlpha * sys.cpuUsage + (1 - cpuAlpha) * smoothedCPU
        if let g = gpu {
            smoothedGPU = cpuAlpha * g + (1 - cpuAlpha) * smoothedGPU
        }

        model.cpu = smoothedCPU
        model.memoryUsed = sys.memoryUsed
        model.memoryTotal = sys.memoryTotal
        model.network = net
        model.gpu = gpu.map { _ in smoothedGPU }
        model.topProcesses = procs

        guard let button = statusItem.button else { return }
        button.image = renderIcon(cpu: smoothedCPU, memory: model.memoryFraction)
        button.toolTip = String(
            format: "CPU %.1f%%   Memory %d%% (%@)",
            smoothedCPU * 100,
            Int((model.memoryFraction * 100).rounded()),
            ByteCountFormatter.string(fromByteCount: Int64(sys.memoryUsed), countStyle: .memory)
        )
    }

    private func renderIcon(cpu: Double, memory: Double) -> NSImage? {
        let renderer = ImageRenderer(content: StatusBarIconView(cpu: cpu, memory: memory))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}

/// 默认 NSPanel + `.nonactivatingPanel` 不能成为 key window，TextField 就拿不到 focus。
/// 覆盖这俩属性让它可以接受键盘输入，同时保持 nonactivating（不抢 Dock 焦点）。
private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
