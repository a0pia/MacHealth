import AppKit
import SwiftUI

/// Mac Sağlığı: pil, depolama, güvenlik ve performansı tek puanda toplar.
@MainActor
final class HealthModel: ObservableObject {
    @Published var battery: BatteryInfo?
    @Published var history: [BatteryHistory.Point] = []
    @Published var security: SecurityStatus?
    @Published var updates: [String]?
    @Published var checkingUpdates = false
    @Published var running: Set<String> = []
    @Published var loaded = false
    /// Disk durumu gövde (body) içinde tekrar tekrar okunmasın diye burada tutulur.
    @Published private(set) var disk = DiskStats.placeholder

    private var timer: Timer?

    func load() async {
        let (b, s, d) = await Task.detached(priority: .userInitiated) { (BatteryService.read(), SecurityStatus.read(), SystemInfo.disk()) }.value
        withAnimation(.spring(duration: 0.5)) {
            disk = d
            battery = b
            security = s
            if let b { history = BatteryHistory.record(b) }
            loaded = true
        }
    }

    func startLive() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor [weak self] in
                let b = await Task.detached { BatteryService.read() }.value
                withAnimation { self?.battery = b }
            }
        }
    }

    func stopLive() { timer?.invalidate(); timer = nil }

    func checkUpdates() async {
        checkingUpdates = true
        let list = await Task.detached { SoftwareUpdates.check() }.value
        withAnimation { updates = list; checkingUpdates = false }
    }

    // MARK: - Kategoriler

    struct Category: Identifiable {
        let id: String
        let title: String
        let icon: String
        let score: Int
        let value: String
        let detail: String
    }

    func categories(speed: SpeedUpModel) -> [Category] {
        var list: [Category] = []
        if let b = battery {
            let score = min(100, max(0, Int((b.health - 0.6) / 0.35 * 100)))
            list.append(Category(id: "battery", title: "Pil", icon: b.isCharging ? "battery.100.bolt" : "battery.75",
                                 score: score, value: "%\(b.healthPercent)", detail: "\(b.cycleCount) döngü · \(b.condition)"))
        }
        if let s = security {
            let off = securityIssues(s).count
            list.append(Category(id: "security", title: "Güvenlik", icon: "lock.shield", score: max(0, 100 - off * 25),
                                 value: off == 0 ? "Tam" : "\(off) eksik", detail: off == 0 ? "Tüm korumalar açık" : securityIssues(s).joined(separator: ", ")))
            let smartOK = (s.smart ?? "Verified").lowercased().contains("verified")
            let diskScore = smartOK ? min(100, Int(disk.freeFraction / 0.25 * 100)) : 20   // %25+ boş = tam puan
            list.append(Category(id: "storage", title: "Depolama", icon: "internaldrive", score: max(diskScore, smartOK ? 40 : 0),
                                 value: "\(Format.bytes(disk.available))", detail: "boş · SMART: \(smartOK ? "Sağlıklı" : (s.smart ?? "?"))"))
        }
        if speed.loaded {
            list.append(Category(id: "performance", title: "Performans", icon: "speedometer", score: speed.score,
                                 value: "\(speed.score)", detail: speed.checks.first { $0.level != .good }?.title ?? "Her şey yolunda"))
        }
        return list
    }

    func overall(speed: SpeedUpModel) -> Int? {
        let c = categories(speed: speed)
        guard !c.isEmpty else { return nil }
        return c.reduce(0) { $0 + $1.score } / c.count
    }

    func securityIssues(_ s: SecurityStatus) -> [String] {
        var out: [String] = []
        if s.firewall == false { out.append("Güvenlik duvarı") }
        if s.fileVault == false { out.append("FileVault") }
        if s.gatekeeper == false { out.append("Gatekeeper") }
        if s.sip == false { out.append("SIP") }
        if s.autoUpdates == false { out.append("Otomatik güncelleme") }
        return out
    }

    // MARK: - Eylemler

    func enableFirewall(using state: AppState) {
        runAdmin(id: "firewall", "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on", done: "Güvenlik duvarı açıldı", using: state)
    }

    func enableGatekeeper(using state: AppState) {
        runAdmin(id: "gatekeeper", "spctl --master-enable", done: "Gatekeeper açıldı", using: state)
    }

    func setLowPower(_ on: Bool, using state: AppState) {
        runAdmin(id: "lowpower", "pmset -a lowpowermode \(on ? 1 : 0)", done: on ? "Düşük Güç Modu açıldı" : "Düşük Güç Modu kapatıldı", using: state)
    }

    private func runAdmin(id: String, _ cmd: String, done: String, using state: AppState) {
        running.insert(id)
        Task {
            let out = await Task.detached { Shell.runAsAdmin(cmd) }.value
            running.remove(id)
            if out.ok {
                ActivityLog.append("SAĞLIK \(done)")
                state.showToast(done)
                await load()
            } else if !out.stderr.contains("-128") {
                state.showToast("İşlem başarısız oldu")
            }
        }
    }
}

enum SettingsLinks {
    static let battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
    static let security = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    static let softwareUpdate = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
}

// MARK: - Tek tıkla optimize

@MainActor
final class OptimizeRunner: ObservableObject {
    enum StepState: Equatable { case pending, running, done(String), failed(String), skipped }

    struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let admin: Bool
        var on: Bool = true
        var state: StepState = .pending
    }

    @Published var steps: [Step]
    @Published var isRunning = false
    @Published var finished = false

    init(firewallOff: Bool) {
        var s: [Step] = [
            Step(id: "junk", title: "Sistem çöpünü temizle", detail: "Sadece \"Güvenli\" işaretli önbellek, log ve geçici dosyalar", icon: "trash", admin: false),
            Step(id: "launchservices", title: "Launch Services'i onar", detail: "\"Birlikte Aç\" menüsünü ve uygulama kayıtlarını düzeltir", icon: "arrow.up.forward.app", admin: false),
            Step(id: "purge", title: "Belleği boşalt", detail: "Disk önbelleğini RAM'den atar", icon: "memorychip", admin: true),
            Step(id: "dns", title: "DNS önbelleğini temizle", detail: "Bağlantı sorunlarını giderir", icon: "network", admin: true),
        ]
        if firewallOff {
            s.append(Step(id: "firewall", title: "Güvenlik duvarını aç", detail: "Gelen izinsiz bağlantıları engeller", icon: "lock.shield", admin: true))
        }
        steps = s
    }

    var needsAdmin: Bool { steps.contains { $0.on && $0.admin } }

    func run(state: AppState) async {
        isRunning = true

        // 1) Yönetici gerektirmeyenler
        for i in steps.indices where steps[i].on && !steps[i].admin {
            withAnimation { steps[i].state = .running }
            let result: StepState
            switch steps[i].id {
            case "junk": result = await cleanJunk(state: state)
            case "launchservices":
                let out = await Task.detached {
                    Shell.run(MaintenanceService.lsregister, ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
                }.value
                result = out.ok ? .done("Onarıldı") : .failed("Başarısız")
            default: result = .skipped
            }
            withAnimation(.spring(duration: 0.4)) { steps[i].state = result }
        }

        // 2) Yönetici gerektirenler: tek şifre penceresi
        let adminIdx = steps.indices.filter { steps[$0].on && steps[$0].admin }
        if !adminIdx.isEmpty {
            var cmds: [String] = []
            for i in adminIdx {
                withAnimation { steps[i].state = .running }
                switch steps[i].id {
                case "purge": cmds.append("/usr/sbin/purge")
                case "dns": cmds.append("dscacheutil -flushcache; killall -HUP mDNSResponder")
                case "firewall": cmds.append("/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on")
                default: break
                }
            }
            let before = SystemInfo.memory()
            let out = await Task.detached { Shell.runAsAdmin(cmds.joined(separator: "; ")) }.value
            let after = SystemInfo.memory()
            for i in adminIdx {
                let r: StepState
                if out.stderr.contains("-128") { r = .skipped }
                else if !out.ok { r = .failed("Başarısız") }
                else if steps[i].id == "purge" { r = .done("\(Format.memory(max(0, after.free - before.free))) boşaldı") }
                else { r = .done("Tamam") }
                withAnimation(.spring(duration: 0.4)) { steps[i].state = r }
            }
            ActivityLog.append("OPTİMİZE yönetici adımları: \(out.ok ? "tamam" : "başarısız/iptal")")
        }
        for i in steps.indices where !steps[i].on { steps[i].state = .skipped }
        isRunning = false
        withAnimation { finished = true }
        await state.speedUp.load()
    }

    /// Sistem çöpündeki "Güvenli" gruplardan varsayılan seçili öğeleri Çöp'e taşır.
    private func cleanJunk(state: AppState) async -> StepState {
        let junk = state.junk
        if !junk.hasScanned { await junk.scan() }
        let items = junk.result.groups
            .filter { $0.insight?.risk == .safe && $0.id != "trash" }
            .flatMap { g in g.items.filter { g.defaultSelection.contains($0.url) } }
        guard !items.isEmpty else { return .done("Zaten temiz") }
        let outcome = await Task.detached { TrashService.moveToTrash(items, module: "Optimize") }.value
        HistoryStore.shared.add(outcome.record)
        state.diskMap.invalidateCache()
        let removed = Set(outcome.record.files.map { URL(fileURLWithPath: $0.original) })
        for i in junk.result.groups.indices { junk.result.groups[i].items.removeAll { removed.contains($0.url) } }
        junk.result.groups.removeAll { $0.items.isEmpty }
        junk.selection.subtract(removed)
        return .done("\(Format.bytes(outcome.freed)) temizlendi")
    }
}
