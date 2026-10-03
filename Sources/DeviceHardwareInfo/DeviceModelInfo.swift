import Foundation
import Darwin

/// Snapshot describing device hardware model, marketing name, and OS runtime info.
public struct DeviceModelSnapshot: Sendable, Equatable {
    /// Raw hardware identifier (e.g. "iPhone16,2", "Mac15,3", "iPad14,5").
    public let hardwareIdentifier: String
    /// Marketing name (e.g. "iPhone 15 Pro Max", "MacBook Pro 16-inch (M3 Pro)", "iPad Pro 12.9-inch (6th gen)").
    public let marketingName: String
    /// Operating system version string.
    public let osVersion: String
    /// System uptime in seconds.
    public let uptimeSeconds: TimeInterval
    /// Architecture identifier (e.g. "arm64", "x86_64").
    public let architecture: String

    public init(
        hardwareIdentifier: String,
        marketingName: String,
        osVersion: String,
        uptimeSeconds: TimeInterval,
        architecture: String
    ) {
        self.hardwareIdentifier = hardwareIdentifier
        self.marketingName = marketingName
        self.osVersion = osVersion
        self.uptimeSeconds = uptimeSeconds
        self.architecture = architecture
    }

    /// Formats the uptime into hours, minutes, and seconds.
    public var formattedUptime: String {
        let total = Int(uptimeSeconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return String(format: "%dd %02dh %02dm", days, hours, minutes)
        } else if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%dm %02ds", minutes, seconds)
        }
    }
}

/// Utility for querying Darwin hardware identifiers and mapping to Apple marketing names.
public enum DeviceModelReader: Sendable {
    public static func currentSnapshot() -> DeviceModelSnapshot {
        let hwId = queryMachineIdentifier()
        let marketing = resolveMarketingName(hwId)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let uptime = ProcessInfo.processInfo.systemUptime

        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        return DeviceModelSnapshot(
            hardwareIdentifier: hwId,
            marketingName: marketing,
            osVersion: os,
            uptimeSeconds: uptime,
            architecture: arch
        )
    }

    /// Queries the low-level machine hardware identifier (hw.machine or hw.model).
    public static func queryMachineIdentifier() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        if size > 0 {
            var machine = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 {
                let id = machine.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        // Fallback to hw.model
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &model, &size, nil, 0) == 0 {
                let id = model.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return "Apple Device"
    }

    /// Resolves common Apple device hardware identifiers to user-friendly marketing names.
    public static func resolveMarketingName(_ identifier: String) -> String {
        let mapping: [String: String] = [
            // iPhone 16 series
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            // iPhone 15 series
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14 series
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            // iPhone 13 series
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            // Popular Macs
            "Mac14,2": "MacBook Air 13-inch (M2)",
            "Mac14,15": "MacBook Air 15-inch (M2)",
            "Mac15,2": "MacBook Air 13-inch (M3)",
            "Mac15,13": "MacBook Air 15-inch (M3)",
            "Mac14,9": "MacBook Pro 14-inch (M2 Pro)",
            "Mac14,10": "MacBook Pro 16-inch (M2 Pro/Max)",
            "Mac15,3": "MacBook Pro 14-inch (M3)",
            "Mac15,6": "MacBook Pro 14-inch (M3 Pro/Max)",
            "Mac15,8": "MacBook Pro 16-inch (M3 Max)",
            "Mac14,3": "Mac mini (M2)",
            "Mac14,12": "Mac mini (M2 Pro)",
            "Mac14,8": "Mac Studio (M2 Max)",
            "Mac14,14": "Mac Studio (M2 Ultra)"
        ]

        if let name = mapping[identifier] {
            return name
        }

        // Generic heuristics
        if identifier.hasPrefix("iPhone") {
            return "iPhone (\(identifier))"
        } else if identifier.hasPrefix("iPad") {
            return "iPad (\(identifier))"
        } else if identifier.hasPrefix("Mac") {
            return "Mac (\(identifier))"
        } else if identifier.hasPrefix("Watch") {
            return "Apple Watch (\(identifier))"
        } else if identifier == "x86_64" || identifier == "arm64" {
            return "Apple Simulator (\(identifier))"
        }
        return identifier
    }
}
