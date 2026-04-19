import Foundation
import Darwin

struct ProcessSnapshot: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let cpuUsage: Double       // fraction of one core (0..N where N = core count)
    let memoryBytes: UInt64
}

/// 枚举全系统进程，计算每个进程两次采样间的 CPU 时间增量 → 得到近似"瞬时 CPU 占用"。
/// 原理：`proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` 返回的 `pti_total_user + pti_total_system`
/// 是该进程累计消耗的 CPU 纳秒数，两次采样之差 / 采样间隔 = 占用一个核的比例。
final class ProcessSampler {
    private var previousTimes: [pid_t: UInt64] = [:]
    private var previousSampleAt: Date = .init()

    func sample(top: Int = 3) -> [ProcessSnapshot] {
        let now = Date()
        let elapsed = now.timeIntervalSince(previousSampleAt)
        previousSampleAt = now

        // 第一次 call 得到需要多少字节
        let bufSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufSize > 0 else { return [] }

        let capacity = Int(bufSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualSize = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(capacity * MemoryLayout<pid_t>.size))
        }
        guard actualSize > 0 else { return [] }
        let count = Int(actualSize) / MemoryLayout<pid_t>.size

        var currentTimes: [pid_t: UInt64] = [:]
        currentTimes.reserveCapacity(count)
        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(count)

        for i in 0..<count where pids[i] > 0 {
            let pid = pids[i]
            var info = proc_taskinfo()
            let sz = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            guard sz == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let cpuTime = info.pti_total_user &+ info.pti_total_system
            currentTimes[pid] = cpuTime

            let previous = previousTimes[pid] ?? cpuTime
            let deltaNs = cpuTime &- previous
            let cpuFrac = elapsed > 0
                ? Double(deltaNs) / (elapsed * 1_000_000_000)
                : 0

            snapshots.append(.init(
                pid: pid,
                name: processName(pid: pid),
                cpuUsage: cpuFrac,
                memoryBytes: info.pti_resident_size
            ))
        }

        previousTimes = currentTimes

        return Array(
            snapshots
                .sorted { $0.cpuUsage > $1.cpuUsage }
                .prefix(top)
        )
    }

    private func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_pidpath(pid, buf.baseAddress, UInt32(MAXPATHLEN))
        }
        guard n > 0 else { return "pid \(pid)" }
        let path = String(cString: buffer)
        return (path as NSString).lastPathComponent
    }
}
