import Foundation

/// 远程 agent 每 2 秒推一条 JSON 到 stdout（见 agent/main.go）
struct RemoteSnapshot: Codable {
    let cpu: Double
    let memUsed: UInt64
    let memTotal: UInt64
    let netRxBps: Double
    let netTxBps: Double
    let uptime: Double
    let host: String
    let ts: Int64

    var memoryFraction: Double {
        memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0
    }
}

enum RemoteStatus: Equatable {
    case idle                       // 未配置 host
    case disconnected               // 有 host 但未连接
    case connecting
    case connected(hostname: String)
    case error(String)
}

/// 通过 `ssh <host> <agentPath>` 启动一条常驻 SSH 连接，
/// 读 stdout 的 newline-delimited JSON 流。
@MainActor
final class RemoteSampler: ObservableObject {
    @Published var status: RemoteStatus = .idle
    @Published var snapshot: RemoteSnapshot?

    private var process: Process?
    private var stdinPipe: Pipe?     // 写端持有引用，防止被 GC 关闭导致 ssh 收到 EOF
    private var buffer = Data()
    private var errBuffer = Data()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func connect(host: String, agentPath: String = "./macos-monitor-agent", interval: Double = 2.0) {
        disconnect()
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .idle
            return
        }

        DebugLog.write("[Remote] connecting to \(trimmed) agent=\(agentPath) interval=\(interval)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new",  // 首次连接自动信任，不弹 fingerprint 确认
            trimmed,
            agentPath, "-interval", String(interval)
        ]
        // .app 从 launchd 启动时 env 很干净，把用户的 HOME / SSH_AUTH_SOCK 透传给 ssh
        proc.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe
        stdinPipe = inPipe           // 保住写端，不让 ssh 读到 EOF 导致 agent 立刻退出

        errBuffer = Data()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in self?.consume(data) }
        }
        // 持续读 stderr 到内存，防止进程退出时丢信息
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in
                self?.errBuffer.append(data)
                if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    DebugLog.write("[Remote] ssh stderr: \(line)")
                }
            }
        }

        proc.terminationHandler = { [weak self] process in
            let exitCode = process.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                let errText = String(data: self.errBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DebugLog.write("[Remote] ssh exited code=\(exitCode) stderr=\(errText.isEmpty ? "<empty>" : errText)")

                self.process = nil
                self.snapshot = nil
                if exitCode == 0 {
                    self.status = .disconnected
                } else if !errText.isEmpty {
                    self.status = .error(Self.shortenError(errText))
                } else {
                    self.status = .error("exit \(exitCode)")
                }
            }
        }

        do {
            try proc.run()
            process = proc
            status = .connecting
            DebugLog.write("[Remote] ssh pid=\(proc.processIdentifier) spawned")
        } catch {
            DebugLog.write("[Remote] spawn failed: \(error.localizedDescription)")
            status = .error("spawn failed: \(error.localizedDescription)")
        }
    }

    private static func shortenError(_ s: String) -> String {
        // 取最后一行非空错误；SSH 经常前面打 debug / banner 之类的
        let lines = s.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        return lines.last ?? s
    }

    func disconnect() {
        // 先关 stdin（让 agent 优雅退出），再兜底 terminate
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        process?.terminate()
        process = nil
        buffer.removeAll()
        snapshot = nil
        if case .connected = status { status = .disconnected }
        if case .connecting = status { status = .disconnected }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0a) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty else { continue }
            do {
                let snap = try decoder.decode(RemoteSnapshot.self, from: Data(line))
                snapshot = snap
                if case .connected(hostname: snap.host) = status {} else {
                    status = .connected(hostname: snap.host)
                }
            } catch {
                DebugLog.write("[Remote] decode failed: \(error.localizedDescription)")
            }
        }
    }
}
