import Foundation
import Darwin

// MARK: - Snapshots

struct MemorySnapshot: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes) * 100.0, 0), 100)
    }

    var usedGB: Double { Double(usedBytes) / Self.bytesPerGB }
    var totalGB: Double { Double(totalBytes) / Self.bytesPerGB }

    static let bytesPerGB: Double = 1024 * 1024 * 1024
    static let bytesPerMB: Double = 1024 * 1024

    static func formatCompact(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / bytesPerGB
        if gb >= 10 {
            return String(format: "%.1f GB", gb)
        } else if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(bytes) / bytesPerMB
            return String(format: "%.0f MB", mb)
        }
    }

    static func formatDetailed(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / bytesPerGB
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / bytesPerMB
            return String(format: "%.0f MB", mb)
        }
    }
}

struct CPUSnapshot: Sendable {
    let totalUsage: Double       // 0...100 (resumo agregado de todos os núcleos)
    let userUsage: Double        // 0...100
    let systemUsage: Double      // 0...100
    let idleUsage: Double        // 0...100
    let perCoreUsage: [Double]   // 0...100 por núcleo
    let coreCount: Int
    let loadAverage: (Double, Double, Double)

    static let empty = CPUSnapshot(
        totalUsage: 0,
        userUsage: 0,
        systemUsage: 0,
        idleUsage: 100,
        perCoreUsage: Array(repeating: 0, count: ProcessInfo.processInfo.processorCount),
        coreCount: ProcessInfo.processInfo.processorCount,
        loadAverage: (0, 0, 0)
    )
}

// MARK: - Sampler (Mach & sysctl)

final class SystemSampler {
    private struct CoreTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private var previousTicks: [CoreTicks] = []
    private let pageSize: UInt64

    init() {
        var ps: vm_size_t = 0
        if host_page_size(mach_host_self(), &ps) == KERN_SUCCESS && ps > 0 {
            pageSize = UInt64(ps)
        } else {
            pageSize = UInt64(getpagesize())
        }
        // Coleta linha de base inicial de ticks para o primeiro delta já vir preciso
        previousTicks = readCoreTicks()
    }

    // MARK: Memória (compatível com o cálculo do Monitor de Atividade do macOS)

    func sampleMemory() -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory

        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let kerr = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        let (swapUsed, swapTotal) = readSwapUsage()

        guard kerr == KERN_SUCCESS else {
            return MemorySnapshot(
                totalBytes: total,
                usedBytes: 0,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: total,
                swapUsedBytes: swapUsed,
                swapTotalBytes: swapTotal
            )
        }

        let internalPages = UInt64(vmStat.internal_page_count)
        let purgeablePages = UInt64(vmStat.purgeable_count)
        let appPages = internalPages > purgeablePages ? (internalPages - purgeablePages) : 0

        let appBytes = appPages * pageSize
        let wiredBytes = UInt64(vmStat.wire_count) * pageSize
        let compressedBytes = UInt64(vmStat.compressor_page_count) * pageSize
        let cachedBytes = (UInt64(vmStat.external_page_count) + purgeablePages) * pageSize
        let freeBytes = UInt64(vmStat.free_count) * pageSize

        // Memória usada (Activity Monitor) = App + Wired + Comprimida
        let usedBytes = min(appBytes + wiredBytes + compressedBytes, total)

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal
        )
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let res = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        guard res == 0 else { return (0, 0) }
        return (swap.xsu_used, swap.xsu_total)
    }

    // MARK: CPU (resumo agregado de todos os núcleos + uso individual)

    func sampleCPU() -> CPUSnapshot {
        let current = readCoreTicks()
        let load = readLoadAverage()

        guard !current.isEmpty else {
            return CPUSnapshot(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 100,
                perCoreUsage: [],
                coreCount: ProcessInfo.processInfo.processorCount,
                loadAverage: load
            )
        }

        defer { previousTicks = current }

        guard previousTicks.count == current.count else {
            return CPUSnapshot(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 100,
                perCoreUsage: Array(repeating: 0, count: current.count),
                coreCount: current.count,
                loadAverage: load
            )
        }

        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        var sumUser: UInt64 = 0
        var sumSystem: UInt64 = 0
        var sumIdle: UInt64 = 0
        var sumNice: UInt64 = 0

        for i in 0..<current.count {
            let cur = current[i]
            let prev = previousTicks[i]

            let dUser = UInt64(cur.user &- prev.user)
            let dSystem = UInt64(cur.system &- prev.system)
            let dIdle = UInt64(cur.idle &- prev.idle)
            let dNice = UInt64(cur.nice &- prev.nice)

            let dTotal = dUser + dSystem + dIdle + dNice
            if dTotal > 0 {
                let active = dUser + dSystem + dNice
                perCore.append(min(max(Double(active) / Double(dTotal) * 100.0, 0), 100))
            } else {
                perCore.append(0)
            }

            sumUser += dUser
            sumSystem += dSystem
            sumIdle += dIdle
            sumNice += dNice
        }

        let grandTotal = sumUser + sumSystem + sumIdle + sumNice
        guard grandTotal > 0 else {
            return CPUSnapshot(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 100,
                perCoreUsage: perCore,
                coreCount: current.count,
                loadAverage: load
            )
        }

        let userPct = Double(sumUser + sumNice) / Double(grandTotal) * 100.0
        let sysPct = Double(sumSystem) / Double(grandTotal) * 100.0
        let idlePct = Double(sumIdle) / Double(grandTotal) * 100.0
        let totalPct = min(max(userPct + sysPct, 0), 100)

        return CPUSnapshot(
            totalUsage: totalPct,
            userUsage: userPct,
            systemUsage: sysPct,
            idleUsage: idlePct,
            perCoreUsage: perCore,
            coreCount: current.count,
            loadAverage: load
        )
    }

    private func readCoreTicks() -> [CoreTicks] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let kerr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard kerr == KERN_SUCCESS, let info = cpuInfo else { return [] }

        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var ticks: [CoreTicks] = []
        ticks.reserveCapacity(Int(numCPUs))

        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(numCPUs) {
            let base = i * stride
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ticks.append(CoreTicks(user: user, system: system, idle: idle, nice: nice))
        }

        return ticks
    }

    private func readLoadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        let res = getloadavg(&loads, 3)
        guard res == 3 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }
}
