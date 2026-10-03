import Foundation
import Darwin

/// Telemetry structure representing disk volume capacity and available storage.
public struct StorageSnapshot: Sendable, Equatable {
    /// Total storage capacity of the primary filesystem in bytes.
    public let totalBytes: UInt64
    /// Raw free storage space in bytes.
    public let freeBytes: UInt64
    /// Storage space available for important usage (accounts for system purgeable caches) in bytes.
    public let availableBytes: UInt64
    /// Total used storage space in bytes.
    public var usedBytes: UInt64 {
        totalBytes > availableBytes ? (totalBytes - availableBytes) : 0
    }
    /// Ratio of used storage to total storage (0.0 to 1.0).
    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public init(totalBytes: UInt64, freeBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
    }

    /// Formats a byte amount into a localized human-readable string (e.g., "512.00 GB").
    public static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Reader for filesystem storage telemetry using Foundation and POSIX statvfs.
public enum StorageReader: Sendable {
    /// Captures a point-in-time snapshot of the primary storage volume.
    public static func currentSnapshot(for path: String = NSHomeDirectory()) -> StorageSnapshot {
        let url = URL(fileURLWithPath: path)

        if let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let rawFree = UInt64(values.volumeAvailableCapacity ?? 0)
            let importantAvail = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(rawFree)))

            if total > 0 {
                return StorageSnapshot(
                    totalBytes: total,
                    freeBytes: rawFree,
                    availableBytes: importantAvail
                )
            }
        }

        // POSIX statvfs fallback
        var stat = statvfs()
        if statvfs(path, &stat) == 0 {
            let blockSize = UInt64(stat.f_frsize)
            let total = UInt64(stat.f_blocks) * blockSize
            let free = UInt64(stat.f_bfree) * blockSize
            let avail = UInt64(stat.f_bavail) * blockSize

            return StorageSnapshot(
                totalBytes: total,
                freeBytes: free,
                availableBytes: avail
            )
        }

        return StorageSnapshot(totalBytes: 0, freeBytes: 0, availableBytes: 0)
    }
}
