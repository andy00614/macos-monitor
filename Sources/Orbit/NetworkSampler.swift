import Foundation
import Darwin

struct NetworkRate {
    let bytesInPerSec: Double
    let bytesOutPerSec: Double
}

/// 读所有非环回接口的累计 rx/tx 字节数（via `getifaddrs` 返回的 `if_data`），
/// 两次采样之差 ÷ 时间 = 近似实时网速。
/// 注意：VPN、虚拟接口（utun、awdl 等）都被计入；如果需要"只看 WiFi"之类的过滤，
/// 可以只累加 en0 / en1 前缀的接口。
final class NetworkSampler {
    private var previousIn: UInt64 = 0
    private var previousOut: UInt64 = 0
    private var previousAt: Date = .init()
    private var primed = false

    func sample() -> NetworkRate {
        let (rx, tx) = readTotals()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousAt)

        defer {
            previousIn = rx
            previousOut = tx
            previousAt = now
            primed = true
        }

        guard primed, elapsed > 0 else {
            return NetworkRate(bytesInPerSec: 0, bytesOutPerSec: 0)
        }

        let dIn = rx &- previousIn
        let dOut = tx &- previousOut
        return NetworkRate(
            bytesInPerSec: Double(dIn) / elapsed,
            bytesOutPerSec: Double(dOut) / elapsed
        )
    }

    private func readTotals() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let p = current {
            let flags = Int32(p.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp = (flags & IFF_UP) != 0

            if !isLoopback, isUp,
               let addr = p.pointee.ifa_addr,
               addr.pointee.sa_family == AF_LINK,
               let dataPtr = p.pointee.ifa_data {
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                rx &+= UInt64(data.ifi_ibytes)
                tx &+= UInt64(data.ifi_obytes)
            }
            current = p.pointee.ifa_next
        }

        return (rx, tx)
    }
}
