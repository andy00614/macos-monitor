import Foundation
import Darwin

struct SystemMetrics {
    let cpuUsage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }
}

final class MetricsSampler {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func sample() -> SystemMetrics {
        let cpu = readCPU()
        let (used, total) = readMemory()
        return SystemMetrics(cpuUsage: cpu, memoryUsed: used, memoryTotal: total)
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &totalSize, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let host = mach_host_self()

        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(host, HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }

        let pageSize = UInt64(vm_kernel_page_size)
        // Activity Monitor 的 "Memory Used" ≈ active + wired + compressed
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize
        return (used, total)
    }

    private func readCPU() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )
        guard err == KERN_SUCCESS, let cpuInfo else { return 0 }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for i in 0..<Int(numCpus) {
            let base = Int(CPU_STATE_MAX) * i
            user   += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]))
            system += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]))
            idle   += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]))
            nice   += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
        }

        defer { previousTicks = (user, system, idle, nice) }

        guard let prev = previousTicks else { return 0 }
        let du = user &- prev.user
        let ds = system &- prev.system
        let di = idle &- prev.idle
        let dn = nice &- prev.nice
        let total = du &+ ds &+ di &+ dn
        guard total > 0 else { return 0 }
        let active = du &+ ds &+ dn
        return Double(active) / Double(total)
    }
}
