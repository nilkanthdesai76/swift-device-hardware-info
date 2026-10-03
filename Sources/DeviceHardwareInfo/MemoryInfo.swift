import Foundation
import Darwin
import MachO

/// Telemetry structure representing system-wide physical memory and app footprint.
public struct MemorySnapshot: Sendable, Equatable {
    /// Total installed physical RAM in bytes.
    public let totalBytes: UInt64
    /// Actively used memory (recently referenced pages) in bytes.
    public let activeBytes: UInt64
    /// Inactive memory (pages that can be paged out or repurposed) in bytes.
    public let inactiveBytes: UInt64
    /// Wired memory (pinned in RAM, cannot be paged to disk) in bytes.
    public let wiredBytes: UInt64
    /// Compressed memory held by macOS/iOS memory compressor in bytes.
    public let compressedBytes: UInt64
    /// Free memory immediately available for allocation in bytes.
    public let freeBytes: UInt64
    /// Total used memory (active + wired + compressed) in bytes.
    public var usedBytes: UInt64 {
        activeBytes + wiredBytes + compressedBytes
    }
    /// Current app process physical memory footprint (`phys_footprint`) in bytes.
    public let appFootprintBytes: UInt64

    /// Ratio of used memory to total memory (0.0 to 1.0).
    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public init(
        totalBytes: UInt64,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        freeBytes: UInt64,
        appFootprintBytes: UInt64
    ) {
        self.totalBytes = totalBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.appFootprintBytes = appFootprintBytes
    }

    /// Formats a byte amount into a localized human-readable string (e.g., "16.00 GB").
    public static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Reader for Darwin / Mach kernel virtual memory statistics.
public enum MemoryReader: Sendable {
    /// Captures a point-in-time snapshot of system and process memory metrics.
    public static func currentSnapshot() -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory

        var pageSize: vm_size_t = 0
        let hostPort = mach_host_self()
        _ = host_page_size(hostPort, &pageSize)
        let pageSize64 = UInt64(pageSize)

        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        var active: UInt64 = 0
        var inactive: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var free: UInt64 = 0

        if kerr == KERN_SUCCESS {
            active = UInt64(vmStat.active_count) * pageSize64
            inactive = UInt64(vmStat.inactive_count) * pageSize64
            wired = UInt64(vmStat.wire_count) * pageSize64
            compressed = UInt64(vmStat.compressor_page_count) * pageSize64
            free = UInt64(vmStat.free_count) * pageSize64
        }

        // Read app process physical footprint
        var taskInfo = task_vm_info_data_t()
        var taskCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        var appFootprint: UInt64 = 0

        let taskErr = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &taskCount)
            }
        }

        if taskErr == KERN_SUCCESS {
            appFootprint = UInt64(taskInfo.phys_footprint)
        }

        return MemorySnapshot(
            totalBytes: total,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            freeBytes: free,
            appFootprintBytes: appFootprint
        )
    }
}
