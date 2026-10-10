import Foundation
import IOKit
import IOKit.ps

// MARK: - Pil

struct BatteryInfo: Sendable {
    var cycleCount: Int
    var designCycles: Int
    /// Tam şarj kapasitesinin fabrika kapasitesine oranı (macOS'un "Maksimum Kapasite" değeri).
    var health: Double
    var designCapacity: Int
    var fullCapacity: Int
    var charge: Int
    var isCharging: Bool
    var pluggedIn: Bool
    var temperature: Double
    var minutesRemaining: Int?
    var adapterWatts: Int?
    var permanentFailure: Bool

    var healthPercent: Int { Int((health * 100).rounded()) }

    var condition: String {
        if permanentFailure { return "Servis gerekli" }
        // macOS ile aynı ölçüt: yuvarlanmış maksimum kapasite %80'in altındaysa
        if healthPercent < 80 { return "Servis önerilir" }
        return "Normal"
    }

    var cycleFraction: Double { designCycles > 0 ? Double(cycleCount) / Double(designCycles) : 0 }
}

enum BatteryService {
    static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ k: String) -> Int? { (dict[k] as? NSNumber)?.intValue }
        let design = int("DesignCapacity") ?? 0
        guard design > 0 else { return nil }
        // Apple Silicon'da MaxCapacity yüzde (100) döner; gerçek değer NominalChargeCapacity / AppleRawMaxCapacity'dir.
        let full = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") ?? int("MaxCapacity") ?? design
        let adapter = (dict["AdapterDetails"] as? [String: Any]).flatMap { ($0["Watts"] as? NSNumber)?.intValue }
        let remaining = int("TimeRemaining") ?? int("AvgTimeToEmpty")

        return BatteryInfo(
            cycleCount: int("CycleCount") ?? 0,
            designCycles: int("DesignCycleCount9C") ?? 1000,
            health: min(1, Double(full) / Double(design)),
            designCapacity: design,
            fullCapacity: full,
            charge: int("CurrentCapacity") ?? 0,
            isCharging: (dict["IsCharging"] as? Bool) ?? false,
            pluggedIn: (dict["ExternalConnected"] as? Bool) ?? false,
            temperature: Double(int("Temperature") ?? 0) / 100,
            minutesRemaining: (remaining ?? 0) > 0 && (remaining ?? 0) < 6000 ? remaining : nil,
            adapterWatts: adapter,
            permanentFailure: (int("PermanentFailureStatus") ?? 0) != 0
        )
    }
}

/// Günde bir kez pil sağlığını kaydeder (trend grafiği için).
enum BatteryHistory {
    struct Point: Codable, Sendable { let date: Date; let health: Double; let cycles: Int }

    private static let url: URL = {
        AppPaths.support.appendingPathComponent("battery.json")
    }()

    static func load() -> [Point] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([Point].self, from: data)) ?? []
    }

    @discardableResult
    static func record(_ b: BatteryInfo) -> [Point] {
        var points = load()
        if let last = points.last, Calendar.current.isDateInToday(last.date) {
            points[points.count - 1] = Point(date: Date(), health: b.health, cycles: b.cycleCount)
        } else {
            points.append(Point(date: Date(), health: b.health, cycles: b.cycleCount))
        }
        points = Array(points.suffix(365))
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(points).write(to: url, options: .atomic)
        return points
    }
}

// MARK: - Güvenlik ve sistem

struct SecurityStatus: Sendable {
    var fileVault: Bool?
    var firewall: Bool?
    var sip: Bool?
    var gatekeeper: Bool?
    var autoUpdates: Bool?
    var smart: String?
    var lowPowerMode: Bool?

    static func read() -> SecurityStatus {
        func out(_ path: String, _ args: [String]) -> String {
            let r = Shell.run(path, args)
            return (r.stdout + r.stderr).lowercased()
        }
        var s = SecurityStatus()
        let fv = out("/usr/bin/fdesetup", ["status"])
        s.fileVault = fv.contains("on") ? true : (fv.contains("off") ? false : nil)
        let fw = out("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        s.firewall = fw.contains("enabled") ? true : (fw.contains("disabled") ? false : nil)
        let sip = out("/usr/bin/csrutil", ["status"])
        s.sip = sip.contains("enabled") ? true : (sip.contains("disabled") ? false : nil)
        let gk = out("/usr/sbin/spctl", ["--status"])
        s.gatekeeper = gk.contains("enabled") ? true : (gk.contains("disabled") ? false : nil)
        let au = out("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "AutomaticCheckEnabled"])
        s.autoUpdates = au.hasPrefix("1") ? true : (au.hasPrefix("0") ? false : true)   // anahtar yoksa varsayılan açık
        let du = Shell.run("/usr/sbin/diskutil", ["info", "disk0"]).stdout
        s.smart = du.split(separator: "\n").first { $0.contains("SMART Status") }
            .map { $0.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "" }
        let pm = out("/usr/bin/pmset", ["-g"])
        if let line = pm.split(separator: "\n").first(where: { $0.contains("lowpowermode") }) {
            s.lowPowerMode = line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
        return s
    }
}

enum SoftwareUpdates {
    /// `softwareupdate -l` (ağ gerektirir, birkaç saniye sürebilir).
    static func check() -> [String] {
        let out = Shell.run("/usr/sbin/softwareupdate", ["-l"]).stdout
        return out.split(separator: "\n")
            .filter { $0.contains("Title:") }
            .map { line in
                let t = line.components(separatedBy: "Title:").last ?? ""
                return t.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? t
            }
    }
}
