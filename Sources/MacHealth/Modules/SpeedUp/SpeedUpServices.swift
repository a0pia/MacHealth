import AppKit
import Foundation

// MARK: - Başlangıç öğeleri

struct StartupItem: Identifiable, Hashable, Sendable {
    enum Scope: String, Sendable { case user = "Kullanıcı", allUsers = "Tüm kullanıcılar", system = "Sistem servisi" }
    var id: String { plist.path }
    let plist: URL
    let label: String
    let program: String
    let scope: Scope
    var enabled: Bool
    /// Bu servisi kuran uygulama (varsa).
    var ownerApp: String? = nil

    var isUpdater: Bool {
        let l = label.lowercased()
        return l.contains("update") || l.contains("updater") || l.contains("autoupdate")
    }

    var displayName: String {
        if let ownerApp { return isUpdater ? "\(ownerApp) güncelleyici" : "\(ownerApp) servisi" }
        let parts = label.split(separator: ".")
        if parts.count >= 2 { return parts.dropFirst().prefix(2).joined(separator: " ").capitalized }
        return label
    }

    /// Kapatırsan ne olur?
    var insight: Insight {
        let app = ownerApp ?? "Bu uygulama"
        if isUpdater {
            return Insight(what: "\(app) için arka planda güncelleme denetleyen servis.",
                           consequences: ["Kapatmak güvenlidir; uygulama çalışmaya devam eder.",
                                          "Güncellemeleri uygulamanın içinden elle yapman gerekir."], risk: .safe)
        }
        if ownerApp != nil {
            return Insight(what: "\(app) uygulamasının arka planda çalışan ana servisi.",
                           consequences: ["Kapatırsan \(app) düzgün çalışmayabilir (ör. VPN bağlanmaz, senkronizasyon durur).",
                                          "Uygulamayı kullanmıyorsan kapatmak yerine Uygulamalar'dan tamamen kaldırmak daha iyi olur.",
                                          "Tekrar açarak eski haline döndürebilirsin."], risk: .caution)
        }
        return Insight(what: "Açılışta kendiliğinden çalışan bir arka plan servisi (\(label)).",
                       consequences: ["Hangi uygulamaya ait olduğu bulunamadı; tanımıyorsan kapatıp Mac'in normal çalıştığını kontrol et.",
                                      "Tekrar açarak eski haline döndürebilirsin."], risk: .low)
    }

    /// launchctl alanı (domain)
    var domain: String { scope == .system ? "system" : "gui/\(getuid())" }
}

enum StartupService {
    static func list() -> [StartupItem] {
        if Demo.isOn { return Demo.startup }
        let home = SafetyGuard.home
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .allUsers),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .system),
        ]
        let guiDisabled = disabledMap(domain: "gui/\(getuid())")
        let sysDisabled = disabledMap(domain: "system")

        var items: [StartupItem] = []
        for (dir, scope) in sources {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for n in names where n.hasSuffix(".plist") {
                let u = dir.appendingPathComponent(n)
                guard let dict = NSDictionary(contentsOf: u) else { continue }
                let label = dict["Label"] as? String ?? (n as NSString).deletingPathExtension
                let program = (dict["Program"] as? String) ?? ((dict["ProgramArguments"] as? [String])?.first ?? "")
                let map = scope == .system ? sysDisabled : guiDisabled
                let plistDisabled = dict["Disabled"] as? Bool ?? false
                let enabled = !(map[label] ?? plistDisabled)
                items.append(StartupItem(plist: u, label: label, program: program, scope: scope, enabled: enabled,
                                         ownerApp: owner(label: label, program: program)))
            }
        }
        return items.sorted { $0.label < $1.label }
    }

    /// Servisin ait olduğu uygulama: program yolundaki .app ya da bundle id öneki.
    private static func owner(label: String, program: String) -> String? {
        if let r = program.range(of: ".app/") {
            let appPath = String(program[..<r.lowerBound]) + ".app"
            return (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }
        var parts = label.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                return url.deletingPathExtension().lastPathComponent
            }
            parts.removeLast()
        }
        // Bilinen üreticiler
        let vendors = ["microsoft": "Microsoft Office", "oracle.java": "Java", "google": "Google", "adobe": "Adobe", "cloudflare": "Cloudflare WARP"]
        return vendors.first { label.lowercased().contains($0.key) }?.value
    }

    /// `launchctl print-disabled` çıktısı: "label" => disabled
    private static func disabledMap(domain: String) -> [String: Bool] {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain]).stdout
        var map: [String: Bool] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            map[label] = value == "disabled" || value == "true"
        }
        return map
    }

    /// Öğeyi açar/kapatır. Sistem servisleri yönetici şifresi ister.
    static func setEnabled(_ item: StartupItem, _ enabled: Bool) -> Shell.Output {
        let target = "\(item.domain)/\(item.label)"
        if item.scope == .system {
            let cmd = enabled
                ? "launchctl enable \(target) && launchctl bootstrap system '\(item.plist.path)'"
                : "launchctl disable \(target) && launchctl bootout \(target)"
            var out = Shell.runAsAdmin(cmd)
            // bootout/bootstrap zaten durdurulmuş/başlatılmış servis için hata verebilir; enable/disable yeterli.
            if !out.ok && !out.stderr.contains("-128") { out = Shell.runAsAdmin("launchctl \(enabled ? "enable" : "disable") \(target)") }
            return out
        }
        let r = Shell.run("/bin/launchctl", [enabled ? "enable" : "disable", target])
        if enabled {
            Shell.run("/bin/launchctl", ["bootstrap", item.domain, item.plist.path])
        } else {
            Shell.run("/bin/launchctl", ["bootout", target])
        }
        return r
    }
}

// MARK: - Bakım görevleri

struct MaintenanceTask: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let needsAdmin: Bool
    let run: @Sendable () -> Shell.Output
}

enum MaintenanceService {
    static let brew: String? = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    static func localSnapshotCount() -> Int {
        if Demo.isOn { return 0 }
        return Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).stdout
            .split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }

    static var tasks: [MaintenanceTask] {
        var list: [MaintenanceTask] = [
            MaintenanceTask(id: "dns", title: "DNS önbelleğini temizle",
                            detail: "Web siteleri açılmıyor veya yanlış adrese gidiyorsa.", icon: "network", needsAdmin: true) {
                Shell.runAsAdmin("dscacheutil -flushcache; killall -HUP mDNSResponder")
            },
            MaintenanceTask(id: "spotlight", title: "Spotlight'ı yeniden indeksle",
                            detail: "Arama yavaş ya da sonuçlar eksikse. İndeksleme bir süre arka planda sürer.", icon: "magnifyingglass", needsAdmin: true) {
                Shell.runAsAdmin("mdutil -E /")
            },
            MaintenanceTask(id: "launchservices", title: "Launch Services'i onar",
                            detail: "\"Birlikte Aç\" menüsünde çift veya eski uygulamalar görünüyorsa.", icon: "arrow.up.forward.app", needsAdmin: false) {
                Shell.run(lsregister, ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
            },
            MaintenanceTask(id: "fonts", title: "Font önbelleğini temizle",
                            detail: "Yazı tipleri bozuk görünüyor veya uygulamalar yavaş açılıyorsa.", icon: "textformat", needsAdmin: false) {
                let r = Shell.run("/usr/bin/atsutil", ["databases", "-removeUser"])
                Shell.run("/usr/bin/atsutil", ["server", "-shutdown"])
                Shell.run("/usr/bin/atsutil", ["server", "-ping"])
                return r
            },
            MaintenanceTask(id: "snapshots", title: "Time Machine yerel anlık görüntülerini sil",
                            detail: "Diskte \"boş\" görünmeyen alanı geri kazandırır. Harici yedekler etkilenmez.", icon: "clock.arrow.circlepath", needsAdmin: true) {
                Shell.runAsAdmin("tmutil deletelocalsnapshots /")
            },
        ]
        if let brew {
            list.append(MaintenanceTask(id: "brew", title: "Homebrew temizliği",
                                        detail: "Eski paket sürümlerini ve kullanılmayan bağımlılıkları kaldırır.", icon: "mug", needsAdmin: false) {
                let a = Shell.run(brew, ["cleanup", "--prune=all", "-s"])
                let b = Shell.run(brew, ["autoremove"])
                return Shell.Output(status: a.ok && b.ok ? 0 : 1, stdout: a.stdout + b.stdout, stderr: a.stderr + b.stderr)
            })
        }
        return list
    }
}

// MARK: - Sağlık kontrolleri

struct HealthCheck: Identifiable, Sendable {
    enum Level: Int, Sendable { case good, warn, bad }
    enum Fix: Sendable { case module(Module), restart, reduceMotion, none }
    let id: String
    let title: String
    let detail: String
    let level: Level
    let penalty: Int
    let fix: Fix
}

enum HealthService {
    struct Input: Sendable {
        var disk: DiskStats
        var memory: MemoryStats
        var enabledStartupCount: Int
        var heavyProcesses: [ProcessInfoRow]
        var uptime: TimeInterval
        var thermal: ProcessInfo.ThermalState
        var snapshots: Int
    }

    static func evaluate(_ i: Input) -> [HealthCheck] {
        var c: [HealthCheck] = []

        let freePct = Int(i.disk.freeFraction * 100)
        if i.disk.freeFraction < 0.10 {
            c.append(.init(id: "disk", title: "Disk neredeyse dolu", detail: "Sadece %\(freePct) boş. Az boş alan swap'ı ve sistemi yavaşlatır.", level: .bad, penalty: 25, fix: .module(.junk)))
        } else if i.disk.freeFraction < 0.20 {
            c.append(.init(id: "disk", title: "Disk alanı azalıyor", detail: "%\(freePct) boş (\(Format.bytes(i.disk.available))). %20'nin üstünde tutmak iyi olur.", level: .warn, penalty: 10, fix: .module(.largeFiles)))
        } else {
            c.append(.init(id: "disk", title: "Disk alanı yeterli", detail: "\(Format.bytes(i.disk.available)) boş (%\(freePct)).", level: .good, penalty: 0, fix: .none))
        }

        switch i.memory.pressure {
        case .critical:
            c.append(.init(id: "mem", title: "Bellek baskısı kritik", detail: "Uygulamalar yavaşlıyor. Ağır uygulamaları kapat.", level: .bad, penalty: 25, fix: .module(.memory)))
        case .warning:
            c.append(.init(id: "mem", title: "Bellek baskısı yüksek", detail: "RAM sınırda; bazı uygulamaları kapatmak hızlandırır.", level: .warn, penalty: 12, fix: .module(.memory)))
        case .normal:
            c.append(.init(id: "mem", title: "Bellek baskısı normal", detail: "\(Format.memory(i.memory.used)) / \(Format.memory(i.memory.total)) kullanımda.", level: .good, penalty: 0, fix: .none))
        }

        let swapGB = Double(i.memory.swapUsed) / 1_073_741_824
        if swapGB > 4 {
            c.append(.init(id: "swap", title: "Yoğun swap kullanımı", detail: "\(Format.memory(i.memory.swapUsed)) diske yazılıyor. RAM yetmiyor.", level: .bad, penalty: 15, fix: .module(.memory)))
        } else if swapGB > 1.5 {
            c.append(.init(id: "swap", title: "Swap kullanılıyor", detail: "\(Format.memory(i.memory.swapUsed)) swap. Yeniden başlatmak ya da uygulama kapatmak iyi gelir.", level: .warn, penalty: 6, fix: .module(.memory)))
        }

        if i.enabledStartupCount > 12 {
            c.append(.init(id: "startup", title: "Çok fazla başlangıç öğesi", detail: "\(i.enabledStartupCount) arka plan servisi açılışta çalışıyor.", level: .warn, penalty: 10, fix: .none))
        } else {
            c.append(.init(id: "startup", title: "Başlangıç öğeleri makul", detail: "\(i.enabledStartupCount) etkin arka plan servisi.", level: .good, penalty: 0, fix: .none))
        }

        if let top = i.heavyProcesses.first, top.cpu > 60 {
            c.append(.init(id: "cpu", title: "\(top.name) işlemciyi yoruyor", detail: String(format: "%%%.0f CPU kullanıyor.", top.cpu), level: .warn, penalty: 8, fix: .none))
        }

        let days = Int(i.uptime / 86400)
        if days >= 14 {
            c.append(.init(id: "uptime", title: "\(days) gündür yeniden başlatılmadı", detail: "Yeniden başlatmak belleği ve geçici dosyaları sıfırlar.", level: .warn, penalty: 6, fix: .restart))
        }

        switch i.thermal {
        case .serious, .critical:
            c.append(.init(id: "thermal", title: "Mac ısınmış", detail: "Sıcaklık nedeniyle işlemci yavaşlatılıyor.", level: .bad, penalty: 12, fix: .none))
        case .fair:
            c.append(.init(id: "thermal", title: "Mac biraz ısınmış", detail: "Yoğun işlemler performansı düşürebilir.", level: .warn, penalty: 4, fix: .none))
        default: break
        }

        if i.snapshots > 0 {
            c.append(.init(id: "snap", title: "\(i.snapshots) Time Machine anlık görüntüsü", detail: "Yerel anlık görüntüler disk alanı tutuyor olabilir.", level: .warn, penalty: 3, fix: .none))
        }
        return c.sorted { $0.level.rawValue > $1.level.rawValue }
    }

    static func score(_ checks: [HealthCheck]) -> Int { max(0, 100 - checks.reduce(0) { $0 + $1.penalty }) }
}
