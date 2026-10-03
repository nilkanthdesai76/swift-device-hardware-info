import XCTest
@testable import DeviceHardwareInfo

final class DeviceHardwareInfoTests: XCTestCase {

    func testMemoryTelemetryNonZero() {
        let memory = DeviceHardware.memory

        XCTAssertGreaterThan(memory.totalBytes, 0, "Total RAM must be greater than 0")
        XCTAssertGreaterThan(memory.appFootprintBytes, 0, "App memory footprint must be greater than 0")
        XCTAssertGreaterThanOrEqual(memory.usagePercentage, 0.0)
        XCTAssertLessThanOrEqual(memory.usagePercentage, 1.0)

        let formatted = MemorySnapshot.formatBytes(memory.totalBytes)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("B"), "Formatted memory must contain byte unit")
    }

    func testCPUTelemetry() {
        let cpu = DeviceHardware.cpu

        XCTAssertGreaterThanOrEqual(cpu.logicalCoreCount, 1, "Must have at least 1 logical core")
        XCTAssertGreaterThanOrEqual(cpu.activeCoreCount, 1, "Must have at least 1 active core")
        XCTAssertFalse(cpu.chipName.isEmpty, "Chip name must not be empty")

        if !cpu.coreLoads.isEmpty {
            XCTAssertEqual(cpu.coreLoads.count, cpu.logicalCoreCount, "Core loads must match logical core count")
            for load in cpu.coreLoads {
                XCTAssertGreaterThanOrEqual(load.coreIndex, 0)
                XCTAssertGreaterThanOrEqual(load.totalUsagePercentage, 0.0)
            }
            XCTAssertGreaterThanOrEqual(cpu.overallUsagePercentage, 0.0)
            XCTAssertLessThanOrEqual(cpu.overallUsagePercentage, 1.0)
        }
    }

    func testStorageTelemetry() {
        let storage = DeviceHardware.storage

        XCTAssertGreaterThan(storage.totalBytes, 0, "Disk total capacity must be greater than 0")
        XCTAssertGreaterThan(storage.availableBytes, 0, "Available space must be greater than 0")
        XCTAssertLessThanOrEqual(storage.usedBytes, storage.totalBytes)
        XCTAssertGreaterThanOrEqual(storage.usagePercentage, 0.0)
        XCTAssertLessThanOrEqual(storage.usagePercentage, 1.0)

        let formatted = StorageSnapshot.formatBytes(storage.totalBytes)
        XCTAssertFalse(formatted.isEmpty)
    }

    func testDeviceModelTelemetry() {
        let device = DeviceHardware.device

        XCTAssertFalse(device.hardwareIdentifier.isEmpty, "Hardware identifier must not be empty")
        XCTAssertFalse(device.marketingName.isEmpty, "Marketing name must not be empty")
        XCTAssertFalse(device.osVersion.isEmpty, "OS version must not be empty")
        XCTAssertGreaterThan(device.uptimeSeconds, 0, "Uptime must be greater than 0")
        XCTAssertFalse(device.architecture.isEmpty, "Architecture must not be empty")
        XCTAssertFalse(device.formattedUptime.isEmpty, "Formatted uptime must not be empty")

        // Test marketing name resolution
        XCTAssertEqual(DeviceModelReader.resolveMarketingName("iPhone16,1"), "iPhone 15 Pro")
        XCTAssertEqual(DeviceModelReader.resolveMarketingName("iPhone17,1"), "iPhone 16 Pro")
        XCTAssertEqual(DeviceModelReader.resolveMarketingName("Mac14,2"), "MacBook Air 13-inch (M2)")
    }

    func testBatteryTelemetry() {
        let battery = DeviceHardware.battery

        // On macOS / simulator, level may be -1.0 (unsupported) or between 0.0 and 1.0
        if battery.level >= 0.0 {
            XCTAssertLessThanOrEqual(battery.level, 1.0)
            XCTAssertFalse(battery.formattedLevel.isEmpty)
            XCTAssertTrue(battery.formattedLevel.contains("%"))
        } else {
            XCTAssertEqual(battery.formattedLevel, "N/A")
        }
    }

    func testFullReport() {
        let report = DeviceHardware.fullReport()

        XCTAssertNotNil(report.timestamp)
        XCTAssertGreaterThan(report.memory.totalBytes, 0)
        XCTAssertGreaterThan(report.storage.totalBytes, 0)
        XCTAssertFalse(report.device.marketingName.isEmpty)
    }
}
