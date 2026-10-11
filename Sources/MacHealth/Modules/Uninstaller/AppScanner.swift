import AppKit
import Foundation

enum AppCategory: String, CaseIterable, Sendable {
    case unneeded, occasional, essential

    var title: String {
        switch self {
        case .unneeded: "Gereksiz olabilir"
        case .occasional: "Ara sıra"
        case .essential: "Gerekli"
        }
    }

    var icon: String {
        switch self {
        case .unneeded: "moon.zzz"
        case .occasional: "clock"
        case .essential: "star"
        }
    }
}

struct AppInfo: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    var size: Int64 = 0
    var lastUsed: Date?
    var dateAdded: Date?
    var genre: String?
    let isProtected: Bool
    /// Library'deki verileri (ayarlar, önbellek, sohbetler, indirilen içerik…). Arka planda hesaplanır.
    var dataSize: Int64 = 0
    var totalSize: Int64 { size + dataSize }

    var isUnused: Bool { category == .unneeded }

    private var daysSinceUse: Int? { lastUsed.map { Int(Date().timeIntervalSince($0) / 86400) } }

    var category: AppCategory {
        if isProtected { return .essential }
        if let d = daysSinceUse {
            if d <= 30 { return .essential }
            if d >= 180 { return .unneeded }
            return .occasional
        }
        // Hiç açılmamış: 30 günden uzun süredir yüklüyse gereksiz olabilir
        if let added = dateAdded, Date().timeIntervalSince(added) > 30 * 86400 { return .unneeded }
        return .occasional
    }

    /// Kategori için açıklama ve öneri.
    var recommendation: Insight {
        let sizeText = totalSize > 0 ? Format.bytes(totalSize) : "bir miktar"
        switch category {
        case .essential where isProtected:
            return Insight(what: "macOS ile birlikte gelen bir Apple uygulaması.",
                           consequences: ["Sistem bu uygulamaya ihtiyaç duyar; kaldırılamaz."], risk: .caution)
        case .essential:
            return Insight(what: "Bu uygulamayı son \(max(daysSinceUse ?? 0, 1)) gün içinde kullandın.",
                           consequences: ["Düzenli kullandığın bir uygulama; kaldırman önerilmez.",
                                          "Sorun çıkarıyorsa kaldırmak yerine **Sıfırla**'yı deneyebilirsin."], risk: .caution)
        case .occasional:
            return Insight(what: lastUsed.map { "En son \(Format.relative($0)) açıldı." } ?? "Açılma bilgisi bulunamadı.",
                           consequences: ["Ara sıra kullandığın bir uygulama.",
                                          "Yer açman gerekiyorsa kaldırabilirsin; gerektiğinde tekrar kurabilirsin."], risk: .low)
        case .unneeded:
            let when = lastUsed.map { "En son \(Format.relative($0)) açıldı" } ?? "Hiç açılmamış"
            return Insight(what: "\(when) ve \(sizeText) yer kaplıyor.",
                           consequences: ["Uzun süredir kullanmadığın için kaldırmak güvenli görünüyor.",
                                          "Arka planda güncelleyici veya servis çalıştırıyorsa kaldırmak Mac'i de hafifletir."], risk: .safe)
        }
    }
}

enum AppScanner {
    private static let home = SafetyGuard.home
    private static let lib = SafetyGuard.home.appendingPathComponent("Library")

    // MARK: - Uygulama listesi

    static func installedApps() -> [AppInfo] {
        if Demo.isOn { return Demo.apps }
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var urls: [URL] = []
        for root in roots {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for n in names {
                let u = root.appendingPathComponent(n)
                if n.hasSuffix(".app") { urls.append(u) }
                // Bir seviye alt klasör (ör. /Applications/Adobe xyz/)
                else if n != "Utilities", let sub = try? FileManager.default.contentsOfDirectory(atPath: u.path) {
                    urls += sub.filter { $0.hasSuffix(".app") }.map { u.appendingPathComponent($0) }
                }
            }
        }
        return urls.compactMap(info(for:)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func info(for url: URL) -> AppInfo? {
        guard url.pathExtension == "app" else { return nil }
        let bundle = Bundle(url: url)
        let id = bundle?.bundleIdentifier
        let name = url.deletingPathExtension().lastPathComponent
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let isProtected = id?.hasPrefix("com.apple.") == true && !removableAppleApps.contains(id ?? "")
        let genreKey = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        let md = MDItemCreateWithURL(nil, url as CFURL)
        return AppInfo(url: url, name: name, bundleID: id, version: version,
                       lastUsed: md.flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date },
                       dateAdded: md.flatMap { MDItemCopyAttribute($0, kMDItemDateAdded) as? Date } ?? FileSizer.modified(url),
                       genre: genreKey.flatMap { genres[$0] } ?? (genreKey == nil ? nil : "Diğer"),
                       isProtected: isProtected)
    }

    /// App Store'dan gelen ve kaldırılabilen Apple uygulamaları.
    private static let removableAppleApps: Set<String> = [
        "com.apple.garageband10", "com.apple.iMovieApp", "com.apple.iWork.Keynote", "com.apple.iWork.Numbers",
        "com.apple.iWork.Pages", "com.apple.dt.Xcode", "com.apple.TestFlight", "com.apple.FinalCut", "com.apple.logic10",
        "com.apple.MainStage3", "com.apple.Compressor", "com.apple.motionapp", "com.apple.configurator.ui", "com.apple.developer.app",
    ]

    static let genres: [String: String] = [
        "public.app-category.games": "Oyun", "public.app-category.action-games": "Oyun", "public.app-category.adventure-games": "Oyun",
        "public.app-category.arcade-games": "Oyun", "public.app-category.casual-games": "Oyun", "public.app-category.role-playing-games": "Oyun",
        "public.app-category.simulation-games": "Oyun", "public.app-category.strategy-games": "Oyun", "public.app-category.sports-games": "Oyun",
        "public.app-category.puzzle-games": "Oyun", "public.app-category.racing-games": "Oyun", "public.app-category.board-games": "Oyun",
        "public.app-category.card-games": "Oyun", "public.app-category.family-games": "Oyun", "public.app-category.music-games": "Oyun",
        "public.app-category.developer-tools": "Geliştirici", "public.app-category.productivity": "Üretkenlik",
        "public.app-category.business": "İş", "public.app-category.graphics-design": "Tasarım",
        "public.app-category.photography": "Fotoğraf", "public.app-category.video": "Video", "public.app-category.music": "Müzik",
        "public.app-category.entertainment": "Eğlence", "public.app-category.social-networking": "İletişim",
        "public.app-category.utilities": "Araçlar", "public.app-category.education": "Eğitim", "public.app-category.reference": "Başvuru",
        "public.app-category.finance": "Finans", "public.app-category.news": "Haber", "public.app-category.lifestyle": "Yaşam",
        "public.app-category.healthcare-fitness": "Sağlık", "public.app-category.medical": "Sağlık", "public.app-category.travel": "Seyahat",
        "public.app-category.weather": "Hava durumu", "public.app-category.sports": "Spor",
    ]

    // MARK: - Artık dosyalar

    /// Uygulamaya ait Library dosyalarını bulur.
    static func leftovers(for app: AppInfo) -> [CleanItem] {
        if Demo.isOn { return Demo.leftovers(for: app) }
        var keys: [String] = []
        if let id = app.bundleID { keys.append(id.lowercased()) }
        let name = app.name.lowercased()
        if name.count >= 4 { keys.append(name) }
        guard !keys.isEmpty else { return [] }

        let dirs = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
            "Saved Application State", "LaunchAgents", "HTTPStorages", "WebKit", "Cookies", "Logs", "Application Scripts",
        ]
        var found: [CleanItem] = []
        var seen = Set<String>()
        for d in dirs {
            let dir = lib.appendingPathComponent(d)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names where matches(n.lowercased(), keys: keys, bundleID: app.bundleID?.lowercased()) {
                let u = dir.appendingPathComponent(n)
                guard seen.insert(u.path).inserted, SafetyGuard.isDeletable(u) else { continue }
                if Permissions.shouldAvoid(u) {
                    // İçine girmeden listele; boyut ve silme için Tam Disk Erişimi gerekir.
                    found.append(CleanItem(url: u, size: 0, detail: "~/Library/\(d)", caution: "Tam Disk Erişimi gerekir"))
                    continue
                }
                let size = FileSizer.size(of: u)
                // Büyük uygulama verisi (sohbetler, belgeler, kayıtlar olabilir) kendiliğinden seçilmesin.
                let bigData = size > 1024 * 1024 * 1024 && ["Group Containers", "Containers", "Application Support"].contains(d)
                found.append(CleanItem(url: u, size: size, modified: FileSizer.modified(u),
                                       detail: "~/Library/\(d)",
                                       caution: AppScanner.protectedCaution(u) ?? (bigData ? "Kişisel veri olabilir" : nil)))
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    private static func matches(_ entry: String, keys: [String], bundleID: String?) -> Bool {
        let base = normalize(entry)
        for k in keys {
            if base == k || base.hasPrefix(k + ".") { return true }
        }
        if let id = bundleID, base.hasSuffix("." + id) { return true }
        return false
    }

    /// "9699UND7H5.group.com.vendor.app.shared.plist" → "com.vendor.app.shared"
    /// Group Containers adlarındaki takım kimliği (10 karakter) ve "group."/"groups." öneklerini atar.
    static func normalize(_ entry: String) -> String {
        var base = entry.lowercased()
        for ext in [".plist", ".savedstate", ".binarycookies"] where base.hasSuffix(ext) {
            base = String(base.dropLast(ext.count))
        }
        let parts = base.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isLetter || $0.isNumber }),
           parts[0].contains(where: \.isNumber) {
            base = parts[1]
        }
        for prefix in ["group.", "groups."] where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
        }
        return base
    }

    // MARK: - Sahipsiz artıklar

    /// Artık yüklü olmayan uygulamalardan kalan dosyalar.
    static func orphans(installed: [AppInfo]) -> [CleanItem] {
        if Demo.isOn { return Demo.orphans }
        let installedIDs = Set(installed.compactMap { $0.bundleID?.lowercased() })
        // Tam Disk Erişimi olmadan veri kapları ne ölçülebilir ne taşınabilir; her biri ayrı izin sorusu açar.
        let dirs = ["Application Support", "Caches", "Containers", "Group Containers", "Saved Application State", "Preferences", "HTTPStorages", "WebKit"]
            .filter { Permissions.hasFullDiskAccess || !$0.hasSuffix("Containers") }
        var items: [CleanItem] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
            let dir = lib.appendingPathComponent(dirs[i])
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
            var local: [CleanItem] = []
            for n in names {
                let lower = normalize(n)
                let id = lower
                guard looksLikeBundleID(lower) else { continue }
                if lower.hasPrefix("com.apple.") || lower.hasPrefix("apple") { continue }
                // Grup klasörleri aynı üreticinin uygulamalarınca paylaşılır: üreticinin yüklü bir uygulaması varsa dokunma.
                if dirs[i] == "Group Containers" {
                    let vendor = lower.split(separator: ".").prefix(2).joined(separator: ".")
                    if installedIDs.contains(where: { $0.hasPrefix(vendor + ".") }) { continue }
                }
                if installedIDs.contains(lower) || installedIDs.contains(where: { lower.hasPrefix($0 + ".") }) { continue }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { continue }
                if AppPaths.isOwn(lower) { continue }
                let u = dir.appendingPathComponent(n)
                guard SafetyGuard.isDeletable(u) else { continue }
                let s = FileSizer.size(of: u)
                guard s > 0 else { continue }
                local.append(CleanItem(url: u, name: id, size: s, modified: FileSizer.modified(u), detail: "~/Library/\(dirs[i])",
                                       caution: protectedCaution(u)))
            }
            lock.lock(); items += local; lock.unlock()
        }
        return items.sorted { $0.size > $1.size }
    }

    /// macOS, başka uygulamaların Containers klasörlerini korur; Tam Disk Erişimi olmadan taşınamazlar.
    static func protectedCaution(_ url: URL) -> String? {
        let p = url.path
        guard p.contains("/Library/Containers/") || p.contains("/Library/Group Containers/") else { return nil }
        guard Permissions.hasFullDiskAccess else { return "Tam Disk Erişimi gerekir" }
        // Yazma izni varsa sorun yok
        let probe = url.appendingPathComponent(".machealth-probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: nil) {
            try? FileManager.default.removeItem(at: probe)
            return nil
        }
        return "Tam Disk Erişimi gerekir"
    }

    private static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, !s.contains(" ") else { return false }
        let tlds: Set<String> = ["com", "org", "net", "io", "de", "co", "app", "dev", "me", "us", "uk", "tr", "ru", "jp", "fr", "info"]
        return tlds.contains(parts[0].lowercased())
    }
}
