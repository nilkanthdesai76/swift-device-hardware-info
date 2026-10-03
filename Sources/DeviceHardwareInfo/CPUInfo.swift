import Foundation
import Darwin
import MachO

/// Represents load statistics for an individual CPU core.
public struct CPUCoreLoad: Sendable, Equatable {
    public let coreIndex: Int
    public let userPercentage: Double
    public let systemPercentage: Double
    public let idlePercentage: Double
    public let nicePercentage: Double

    public var totalUsagePercentage: Double {
        userPercentage + systemPercentage + nicePercentage
    }

    public init(coreIndex: Int, userPercentage: Double, systemPercentage: Double, idlePercentage: Double, nicePercentage: Double) {
        self.coreIndex = coreIndex
        self.userPercentage = userPercentage
        self.systemPercentage = systemPercentage
        self.idlePercentage = idlePercentage
        self.nicePercentage = nicePercentage
    }
}

/// System-wide CPU and thermal telemetry.
public struct CPUSnapshot: Sendable, Equatable {
    /// Total logical processor cores.
    public let logicalCoreCount: Int
    /// Active processor cores available to the system.
    public let activeCoreCount: Int
    /// Chip architecture brand name (e.g. "Apple M2 Pro", "Apple A17 Pro").
    public let chipName: String
    /// Current system thermal state.
    public let thermalState: ProcessInfo.ThermalState
    /// Per-core load metrics captured during sample.
    public let coreLoads: [CPUCoreLoad]

    /// Average overall CPU usage percentage (0.0 to 1.0) across all active cores.
    public var overallUsagePercentage: Double {
        guard !coreLoads.isEmpty else { return 0.0 }
        let sum = coreLoads.reduce(0.0) { $0 + $1.totalUsagePercentage }
        return sum / Double(coreLoads.count)
    }

    public init(
        logicalCoreCount: Int,
        activeCoreCount: Int,
        chipName: String,
        thermalState: ProcessInfo.ThermalState,
        coreLoads: [CPUCoreLoad]
    ) {
        self.logicalCoreCount = logicalCoreCount
        self.activeCoreCount = activeCoreCount
        self.chipName = chipName
        self.thermalState = thermalState
        self.coreLoads = coreLoads
    }
}

/// Reader for Darwin CPU host statistics and processor load.
public final class CPUReader: @unchecked Sendable {
    private var previousCpuInfo: processor_info_array_t?
    private var previousNumCpuInfo: mach_msg_type_number_t = 0
    private let lock = NSLock()

    public init() {}

    deinit {
        if let previous = previousCpuInfo {
            let size = vm_size_t(previousNumCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: previous)), size)
        }
    }

    /// Captures the latest CPU telemetry snapshot with per-core delta analysis.
    public func currentSnapshot() -> CPUSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let logicalCores = ProcessInfo.processInfo.processorCount
        let activeCores = ProcessInfo.processInfo.activeProcessorCount
        let thermal = ProcessInfo.processInfo.thermalState
        let chip = Self.queryChipName()

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let kerr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )

        guard kerr == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return CPUSnapshot(
                logicalCoreCount: logicalCores,
                activeCoreCount: activeCores,
                chipName: chip,
                thermalState: thermal,
                coreLoads: []
            )
        }

        var coreLoads: [CPUCoreLoad] = []

        if let prevInfo = previousCpuInfo {
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                let userDelta = cpuInfo[offset + Int(CPU_STATE_USER)] - prevInfo[offset + Int(CPU_STATE_USER)]
                let systemDelta = cpuInfo[offset + Int(CPU_STATE_SYSTEM)] - prevInfo[offset + Int(CPU_STATE_SYSTEM)]
                let idleDelta = cpuInfo[offset + Int(CPU_STATE_IDLE)] - prevInfo[offset + Int(CPU_STATE_IDLE)]
                let niceDelta = cpuInfo[offset + Int(CPU_STATE_NICE)] - prevInfo[offset + Int(CPU_STATE_NICE)]

                let total = max(1, userDelta + systemDelta + idleDelta + niceDelta)

                let userPct = max(0.0, min(1.0, Double(userDelta) / Double(total)))
                let sysPct = max(0.0, min(1.0, Double(systemDelta) / Double(total)))
                let idlePct = max(0.0, min(1.0, Double(idleDelta) / Double(total)))
                let nicePct = max(0.0, min(1.0, Double(niceDelta) / Double(total)))

                coreLoads.append(CPUCoreLoad(
                    coreIndex: i,
                    userPercentage: userPct,
                    systemPercentage: sysPct,
                    idlePercentage: idlePct,
                    nicePercentage: nicePct
                ))
            }
            // Deallocate previous info buffer
            let prevSize = vm_size_t(previousNumCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: prevInfo)), prevSize)
        } else {
            // Baseline capture: instantaneous cumulative ticks
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                let user = cpuInfo[offset + Int(CPU_STATE_USER)]
                let sys = cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
                let idle = cpuInfo[offset + Int(CPU_STATE_IDLE)]
                let nice = cpuInfo[offset + Int(CPU_STATE_NICE)]
                let total = max(1, user + sys + idle + nice)

                coreLoads.append(CPUCoreLoad(
                    coreIndex: i,
                    userPercentage: Double(user) / Double(total),
                    systemPercentage: Double(sys) / Double(total),
                    idlePercentage: Double(idle) / Double(total),
                    nicePercentage: Double(nice) / Double(total)
                ))
            }
        }

        previousCpuInfo = cpuInfo
        previousNumCpuInfo = numCpuInfo

        return CPUSnapshot(
            logicalCoreCount: logicalCores,
            activeCoreCount: activeCores,
            chipName: chip,
            thermalState: thermal,
            coreLoads: coreLoads
        )
    }

    /// Queries the chip brand or machine architecture via sysctl.
    public static func queryChipName() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var brand = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0) == 0 {
                let name = brand.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        // Fallback to hw.model
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &model, &size, nil, 0) == 0 {
                let name = model.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) } ?? ""
                }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return "Apple Silicon"
    }
}
