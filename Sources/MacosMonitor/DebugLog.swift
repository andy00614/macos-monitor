import Foundation

/// 极简文件日志：无论 os_log 怎么脱敏，都能从 /tmp/macosmonitor.log 看到
enum DebugLog {
    private static let url = URL(fileURLWithPath: "/tmp/macosmonitor.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let queue = DispatchQueue(label: "com.macosmonitor.debuglog")

    static func write(_ msg: String) {
        queue.async {
            let line = "\(formatter.string(from: Date())) \(msg)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                if let fh = try? FileHandle(forWritingTo: url) {
                    defer { try? fh.close() }
                    try? fh.seekToEnd()
                    try? fh.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
