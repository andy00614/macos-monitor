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

// MARK: - Main popover

struct MenuView: View {
    @ObservedObject var model: MetricsModel
    @State private var launchAtLogin: Bool = LoginItemService.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricRow(
                title: "CPU",
                value: String(format: "%.1f%%", model.cpu * 100),
                fraction: model.cpu
            )
            MetricRow(
                title: "MEMORY",
                value: "\(format(model.memoryUsed)) / \(format(model.memoryTotal))",
                fraction: model.memoryFraction
            )
            if let gpu = model.gpu {
                MetricRow(
                    title: "GPU",
                    value: String(format: "%.0f%%", gpu * 100),
                    fraction: gpu
                )
            }

            IORow(label: "NETWORK", down: model.network.bytesInPerSec, up: model.network.bytesOutPerSec)

            Divider()
            ProcessList(processes: model.topProcesses)

            Divider()
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
        .padding(16)
        .frame(width: 280)
    }

    private func format(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(bytes))
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

// MARK: - Status bar icon (small view rendered via ImageRenderer)

struct StatusBarIconView: View {
    let cpu: Double
    let memory: Double

    var body: some View {
        HStack(spacing: 6) {
            metric(symbol: "cpu", fraction: cpu)
            metric(symbol: "memorychip", fraction: memory)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func metric(symbol: String, fraction: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                Capsule()
                    .fill(color(for: fraction))
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
