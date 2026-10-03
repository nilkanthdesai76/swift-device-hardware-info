import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

#if canImport(IOKit) && os(macOS)
import IOKit.ps
#endif

/// Represents the power and charging state of the device battery.
public enum BatteryChargeState: String, Sendable, Codable {
    case unknown
    case unplugged
    case charging
    case full
}

/// Telemetry snapshot representing battery and thermal status.
public struct BatterySnapshot: Sendable, Equatable {
    /// Battery level percentage (0.0 to 1.0, or -1.0 if not available/supported).
    public let level: Float
    /// Current charging state.
    public let state: BatteryChargeState
    /// True if Low Power Mode is currently active.
    public let isLowPowerModeEnabled: Bool
    /// Current device thermal state.
    public let thermalState: ProcessInfo.ThermalState

    public init(
        level: Float,
        state: BatteryChargeState,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) {
        self.level = level
        self.state = state
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
    }

    /// User-friendly percentage string (e.g., "85%").
    public var formattedLevel: String {
        guard level >= 0 else { return "N/A" }
        return "\(Int(round(level * 100)))%"
    }
}

/// Reader for system battery and thermal management metrics.
public enum BatteryReader: Sendable {
    public static func currentSnapshot() -> BatterySnapshot {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState

        #if canImport(UIKit) && !os(watchOS)
        let device = UIDevice.current
        let prevMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = prevMonitoring }

        let level = device.batteryLevel
        let state: BatteryChargeState
        switch device.batteryState {
        case .unknown: state = .unknown
        case .unplugged: state = .unplugged
        case .charging: state = .charging
        case .full: state = .full
        @unknown default: state = .unknown
        }

        return BatterySnapshot(
            level: level,
            state: state,
            isLowPowerModeEnabled: lowPower,
            thermalState: thermal
        )

        #elseif canImport(IOKit) && os(macOS)
        var level: Float = -1.0
        var state: BatteryChargeState = .unknown

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    if let cur = description[kIOPSCurrentCapacityKey as String] as? Int,
                       let max = description[kIOPSMaxCapacityKey as String] as? Int,
                       max > 0 {
                        level = Float(cur) / Float(max)
                    }

                    if let isCharging = description[kIOPSIsChargingKey as String] as? Bool {
                        if isCharging {
                            state = (level >= 0.99) ? .full : .charging
                        } else if let isPlugged = description[kIOPSIsChargedKey as String] as? Bool, isPlugged {
                            state = .full
                        } else {
                            state = .unplugged
                        }
                    }
                    break
                }
            }
        }

        return BatterySnapshot(
            level: level,
            state: state,
            isLowPowerModeEnabled: lowPower,
            thermalState: thermal
        )

        #else
        return BatterySnapshot(
            level: -1.0,
            state: .unknown,
            isLowPowerModeEnabled: lowPower,
            thermalState: thermal
        )
        #endif
    }
}
