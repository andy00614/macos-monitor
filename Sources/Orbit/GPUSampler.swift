import Foundation
import IOKit

/// 尝试从 IORegistry 的 `IOAccelerator` 类读 `PerformanceStatistics` 字典，
/// 里面有 `Device Utilization %` 等字段。Apple Silicon + 较新 Intel 集显都可用，
/// 无需 entitlement。读不到时返回 nil，UI 层会隐藏 GPU 行。
final class GPUSampler {
    func sample() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else {
                continue
            }
            // 不同代 GPU 驱动字段名略有差异，按常见 key 逐个尝试
            for key in ["Device Utilization %", "GPU Core Utilization", "GPU Busy"] {
                if let value = stats[key] as? Int {
                    return Double(value) / 100.0
                }
                if let value = stats[key] as? Double {
                    return value / 100.0
                }
            }
        }
        return nil
    }
}
