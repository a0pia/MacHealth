import AppKit
import Darwin
import Foundation

struct DiskStats: Sendable {
    var total: Int64
    var available: Int64
    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { 1 - usedFraction }

    /// Görünümlerde başlangıç değeri (gerçek değer .task/.onAppear içinde okunur).
    static let placeholder = DiskStats(total: 0, available: 0)
}

struct MemoryStats: Sendable {
    var total: Int64
    var app: Int64          // uygulama belleği
    var wired: Int64        // kablolu (çekirdek)
    var compressed: Int64   // sıkıştırılmış
    var cached: Int64       // dosya önbelleği (gerekirse hemen boşalır)
    var free: Int64
    var swapUsed: Int64
    var swapTotal: Int64
    var pressure: Pressure

    var used: Int64 { app + wired + compressed }

    static let placeholder = MemoryStats(total: Int64(ProcessInfo.processInfo.physicalMemory), app: 0, wired: 0, compressed: 0,
                                         cached: 0, free: 0, swapUsed: 0, swapTotal: 0, pressure: .normal)
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    enum Pressure: Int, Sendable {
        case normal = 1, warning = 2, critical = 4
        var title: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Yüksek"
            case .critical: "Kritik"
            }
        }
    }
}

struct ProcessInfoRow: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let path: String
    let cpu: Double
    let memory: Int64
    var id: Int32 { pid }
}

enum SystemInfo {
    static func disk() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let avail = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return DiskStats(total: total, available: avail)
    }

    static func memory() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(vm_kernel_page_size)
        var app: Int64 = 0, wired: Int64 = 0, compressed: Int64 = 0, cached: Int64 = 0, free: Int64 = 0
        if result == KERN_SUCCESS {
            app = Int64(stats.internal_page_count - stats.purgeable_count) * page
            wired = Int64(stats.wire_count) * page
            compressed = Int64(stats.compressor_page_count) * page
            cached = Int64(stats.external_page_count + stats.purgeable_count) * page
            free = Int64(stats.free_count) * page
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)

        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0)

        return MemoryStats(
            total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
            swapUsed: Int64(swap.xsu_used), swapTotal: Int64(swap.xsu_total),
            pressure: MemoryStats.Pressure(rawValue: Int(level)) ?? .normal
        )
    }

    /// `ps` ile çalışan işlemler.
    static func processes() -> [ProcessInfoRow] {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="]).stdout
        // Uygulama adlarını tek seferde al (her işlem için ayrı sorgu yapma).
        var names: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications { if let n = app.localizedName { names[app.processIdentifier] = n } }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = Int64(parts[2]) else { return nil }
            let path = String(parts[3])
            return ProcessInfoRow(pid: pid, name: names[pid] ?? (path as NSString).lastPathComponent, path: path, cpu: cpu, memory: rss * 1024)
        }
    }

    /// İşlem simgeleri önbelleği (her çizimde NSRunningApplication sorgulanmasın).
    @MainActor private static var iconCache: [Int32: NSImage?] = [:]

    @MainActor static func icon(for pid: Int32) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let img = NSRunningApplication(processIdentifier: pid)?.icon
        if iconCache.count > 400 { iconCache.removeAll() }
        iconCache[pid] = img
        return img
    }

    static var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }

    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
