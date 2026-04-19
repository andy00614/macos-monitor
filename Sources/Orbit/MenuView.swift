import SwiftUI
import AppKit

final class MetricsModel: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var network: NetworkRate = .init(bytesInPerSec: 0, bytesOutPerSec: 0)
    @Published var gpu: Double? = nil
    @Published var topProcesses: [ProcessSnapshot] = []

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }
}

// MARK: - Container: stacks Local + Remote sections

struct MenuView: View {
    @ObservedObject var model: MetricsModel
    @ObservedObject var remote: RemoteSampler

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSection(model: model)
            sectionDivider
            RemoteSection(remote: remote)
            sectionDivider
            FooterRow()
                .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 12)
    }
}

// MARK: - Local section

private struct LocalSection: View {
    @ObservedObject var model: MetricsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "THIS MAC", dotColor: .green, trailing: EmptyView())
            MetricRow(title: "CPU",
                      value: String(format: "%.1f%%", model.cpu * 100),
                      fraction: model.cpu)
            MetricRow(title: "MEMORY",
                      value: "\(format(model.memoryUsed)) / \(format(model.memoryTotal))",
                      fraction: model.memoryFraction)
            if let gpu = model.gpu {
                MetricRow(title: "GPU",
                          value: String(format: "%.0f%%", gpu * 100),
                          fraction: gpu)
            }
            IORow(label: "NETWORK",
                  down: model.network.bytesInPerSec,
                  up: model.network.bytesOutPerSec)
            Divider().padding(.vertical, 4)
            ProcessList(processes: model.topProcesses)
        }
    }

    private func format(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Remote section (inline, no tab)

private struct RemoteSection: View {
    @ObservedObject var remote: RemoteSampler
    @State private var hostDraft: String = UserDefaults.standard.string(forKey: "remoteHost") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: sectionTitle, dotColor: statusColor, trailing: trailingControl)
            switch remote.status {
            case .idle, .disconnected:
                configForm
            case .error(let msg):
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .truncationMode(.tail)
                configForm
            case .connecting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            case .connected:
                if let s = remote.snapshot {
                    connectedMetrics(s)
                } else {
                    Text("Waiting for first sample…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
        }
    }

    private var sectionTitle: String {
        switch remote.status {
        case .idle:                  return "REMOTE"
        case .disconnected:          return "REMOTE · DISCONNECTED"
        case .connecting:            return "REMOTE · CONNECTING"
        case .connected(let h):      return "REMOTE · \(h.uppercased())"
        case .error:                 return "REMOTE · ERROR"
        }
    }

    private var statusColor: Color {
        switch remote.status {
        case .connected:            return .green
        case .connecting:           return .orange
        case .error:                return .red
        case .idle, .disconnected:  return Color(nsColor: .tertiaryLabelColor)
        }
    }

    @ViewBuilder private var trailingControl: some View {
        if case .connected = remote.status {
            Button("Disconnect") { remote.disconnect() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        } else if case .error = remote.status {
            Button("Retry") {
                let saved = UserDefaults.standard.string(forKey: "remoteHost") ?? ""
                if !saved.isEmpty { remote.connect(host: saved) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }

    @ViewBuilder private var configForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SSH HOST")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            TextField("user@host or ssh alias", text: $hostDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(connect)
            HStack {
                Spacer()
                Button {
                    connect()
                } label: {
                    Text("Connect")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(hostDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Requires orbit-agent at ~/orbit-agent on the remote.")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func connect() {
        let trimmed = hostDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: "remoteHost")
        remote.connect(host: trimmed)
    }

    @ViewBuilder
    private func connectedMetrics(_ s: RemoteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricRow(title: "CPU",
                      value: String(format: "%.1f%%", s.cpu * 100),
                      fraction: s.cpu)
            MetricRow(title: "MEMORY",
                      value: "\(format(s.memUsed)) / \(format(s.memTotal))",
                      fraction: s.memoryFraction)
            IORow(label: "NETWORK", down: s.netRxBps, up: s.netTxBps)
            HStack {
                Text("UPTIME")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Text(formatUptime(s.uptime))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        }
    }

    private func format(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(bytes))
    }

    private func formatUptime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Section header (status dot + uppercase label + optional trailing control)

private struct SectionHeader<Trailing: View>: View {
    let title: String
    let dotColor: Color
    let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Spacer()
            trailing
        }
    }
}

// MARK: - Footer (Launch at login + Quit)

private struct FooterRow: View {
    @State private var launchAtLogin: Bool = LoginItemService.isEnabled

    var body: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .onChange(of: launchAtLogin) { newValue in
                    LoginItemService.setEnabled(newValue)
                }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }
}

// MARK: - Reusable rows

private struct MetricRow: View {
    let title: String
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            ProgressBar(fraction: fraction)
        }
    }
}

private struct IORow: View {
    let label: String
    let down: Double
    let up: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 60, alignment: .leading)
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text(formatRate(down))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text(formatRate(up))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        }
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .decimal
        return f.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

private struct ProcessList: View {
    let processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP PROCESSES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            if processes.isEmpty {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            } else {
                ForEach(processes) { p in
                    HStack {
                        Text(p.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.1f%%", p.cpuUsage * 100))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }
}

// MARK: - Status bar icon

/// 远程侧的图标渲染参数。nil = 未配置，菜单栏图标回到"仅本地"紧凑模式。
struct RemoteIconInfo {
    let cpu: Double
    let memory: Double
    let connected: Bool      // false 时 bar 去饱和，仍占空间但视觉上静默
}

struct StatusBarIconView: View {
    let cpu: Double
    let memory: Double
    let remote: RemoteIconInfo?

    var body: some View {
        HStack(spacing: 6) {
            metric(symbol: "cpu",        fraction: cpu,    active: true)
            metric(symbol: "memorychip", fraction: memory, active: true)
            if let r = remote {
                Rectangle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 1, height: 10)
                    .padding(.horizontal, 1)
                metric(symbol: "server.rack", fraction: r.cpu,    active: r.connected)
                metric(symbol: "memorychip",  fraction: r.memory, active: r.connected)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func metric(symbol: String, fraction: Double, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: active ? .labelColor : .tertiaryLabelColor))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                Capsule()
                    .fill(active ? color(for: fraction) : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 14 * CGFloat(min(max(fraction, 0), 1)))
            }
            .frame(width: 14, height: 4)
        }
    }

    private func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6:  return .green
        case ..<0.85: return .orange
        default:      return .red
        }
    }
}

// MARK: - Shared progress bar

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(fillColor)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 4)
    }

    private var fillColor: Color {
        switch fraction {
        case ..<0.6:  return .green
        case ..<0.85: return .orange
        default:      return .red
        }
    }
}
