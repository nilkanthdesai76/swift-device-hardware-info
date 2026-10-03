import Foundation

/// Unified diagnostic report combining all hardware subsystems into a single snapshot.
public struct SystemHardwareReport: Sendable, Equatable {
    public let timestamp: Date
    public let device: DeviceModelSnapshot
    public let memory: MemorySnapshot
    public let cpu: CPUSnapshot
    public let storage: StorageSnapshot
    public let battery: BatterySnapshot

    public init(
        timestamp: Date = Date(),
        device: DeviceModelSnapshot,
        memory: MemorySnapshot,
        cpu: CPUSnapshot,
        storage: StorageSnapshot,
        battery: BatterySnapshot
    ) {
        self.timestamp = timestamp
        self.device = device
        self.memory = memory
        self.cpu = cpu
        self.storage = storage
        self.battery = battery
    }
}

/// Primary developer facade for querying Apple device hardware telemetry.
public enum DeviceHardware: Sendable {
    /// Captures the latest memory telemetry (RAM usage, active/wired pages, app memory footprint).
    public static var memory: MemorySnapshot {
        MemoryReader.currentSnapshot()
    }

    /// Captures the latest CPU telemetry (core counts, per-core load, thermal state).
    public static var cpu: CPUSnapshot {
        sharedCPUReader.currentSnapshot()
    }

    /// Captures the primary storage capacity, free space, and available space.
    public static var storage: StorageSnapshot {
        StorageReader.currentSnapshot()
    }

    /// Captures device hardware model, machine identifier, and uptime.
    public static var device: DeviceModelSnapshot {
        DeviceModelReader.currentSnapshot()
    }

    /// Captures battery level, power state, and thermal status.
    public static var battery: BatterySnapshot {
        BatteryReader.currentSnapshot()
    }

    /// Captures a synchronized report containing all hardware subsystems.
    public static func fullReport() -> SystemHardwareReport {
        SystemHardwareReport(
            device: device,
            memory: memory,
            cpu: cpu,
            storage: storage,
            battery: battery
        )
    }

    private static let sharedCPUReader = CPUReader()
}
