import Foundation

/// Büyük ve eski dosyalar, indirilenler, iOS yedekleri ve macOS yükleyicileri.
enum LargeFilesScanner {
    private static let home = SafetyGuard.home

    struct Options: Sendable {
        var minSize: Int64 = 100 * 1024 * 1024
        var oldAfterDays: Int = 365
    }

    static func scan(_ options: Options) -> ScanResult {
        if Demo.isOn { return Demo.largeFiles }
        var denied: [String] = []
        let (large, old) = walkHome(options)
        let backups = iosBackups(denied: &denied)
        return ScanResult(groups: [
            CleanGroup(id: "large", title: "Büyük dosyalar", icon: "doc.badge.ellipsis",
                       note: "\(Format.bytes(options.minSize)) üzerindeki dosyalar. Kişisel dosyaların olabilir, dikkatle seç.",
                       items: large, selectedByDefault: false),
            CleanGroup(id: "old", title: "Eski dosyalar", icon: "calendar.badge.clock",
                       note: "\(options.oldAfterDays / 30) aydan uzun süredir açılmamış 10 MB üzeri dosyalar.",
                       items: old, selectedByDefault: false),
            installers(),
            oldDownloads(),
            backups,
            macOSInstallers(),
        ].filter { !$0.items.isEmpty }, deniedPaths: denied)
    }

    // MARK: - Ana klasör taraması

    private static func walkHome(_ o: Options) -> ([CleanItem], [CleanItem]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentModificationDateKey, .contentAccessDateKey, .isPackageKey]
        let skipTop: Set<String> = ["Library", ".Trash"]
        let oldCutoff = Date().addingTimeInterval(-Double(o.oldAfterDays) * 24 * 3600)
        let oldMin: Int64 = 10 * 1024 * 1024

        let tops = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { !skipTop.contains($0) && !$0.hasPrefix(".") }
            .map { home.appendingPathComponent($0) }

        var large: [CleanItem] = [], old: [CleanItem] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: tops.count) { i in
            guard let e = FileManager.default.enumerator(at: tops[i], includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            else { return }
            var l: [CleanItem] = [], od: [CleanItem] = []
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                // Fotoğraflar kütüphanesi gibi paketlerin içine girme.
                if v.isPackage == true {
                    if url.pathExtension == "photoslibrary" || url.pathExtension == "app" { e.skipDescendants(); continue }
                }
                guard v.isRegularFile == true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let lastUsed = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
                if size >= o.minSize {
                    l.append(CleanItem(url: url, size: size, modified: v.contentModificationDate,
                                       detail: shortPath(url.deletingLastPathComponent())))
                } else if size >= oldMin && lastUsed < oldCutoff {
                    od.append(CleanItem(url: url, size: size, modified: lastUsed,
                                        detail: "Son kullanım: \(Format.date(lastUsed)) · \(shortPath(url.deletingLastPathComponent()))"))
                }
            }
            lock.lock(); large += l; old += od; lock.unlock()
        }
        return (large.sorted { $0.size > $1.size }, old.sorted { $0.size > $1.size })
    }

    // MARK: - İndirilenler

    private static var downloads: URL { home.appendingPathComponent("Downloads") }

    private static func installers() -> CleanGroup {
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
        let items = FileSizer.children(of: downloads).filter { exts.contains($0.url.pathExtension.lowercased()) }
        return CleanGroup(id: "installers", title: "Kurulum dosyaları", icon: "shippingbox",
                          note: "İndirilenler'deki .dmg / .pkg dosyaları. Uygulama kurulduysa artık gerekmez.", items: items)
    }

    private static func oldDownloads() -> CleanGroup {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let skip: Set<String> = ["dmg", "pkg", "mpkg", "iso", "crdownload", "part", "download"]
        let items = FileSizer.children(of: downloads)
            .filter { !skip.contains($0.url.pathExtension.lowercased()) && ($0.modified ?? .distantFuture) < cutoff }
        return CleanGroup(id: "oldDownloads", title: "Eski indirmeler", icon: "arrow.down.circle",
                          note: "30 günden eski indirilenler.", items: items, selectedByDefault: false)
    }

    // MARK: - iOS yedekleri

    private static func iosBackups(denied: inout [String]) -> CleanGroup {
        let dir = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        if FileSizer.exists(dir) && !FileSizer.isReadable(dir) { denied.append(dir.path) }
        let items = FileSizer.children(of: dir).map { item -> CleanItem in
            var i = item
            if let info = NSDictionary(contentsOf: item.url.appendingPathComponent("Info.plist")) {
                let name = info["Device Name"] as? String ?? "iOS cihazı"
                let date = info["Last Backup Date"] as? Date
                let product = info["Product Type"] as? String ?? ""
                i.name = name
                i.modified = date ?? i.modified
                i.detail = "\(product) · Son yedek: \(Format.date(date ?? i.modified))"
            }
            return i
        }
        return CleanGroup(id: "iosBackups", title: "iPhone / iPad yedekleri", icon: "iphone",
                          note: "Finder ile alınmış yerel yedekler. iCloud yedeklerini etkilemez.",
                          items: items, selectedByDefault: false)
    }

    // MARK: - macOS yükleyicileri

    private static func macOSInstallers() -> CleanGroup {
        let apps = URL(fileURLWithPath: "/Applications")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
        let items = names.filter { $0.hasPrefix("Install macOS") && $0.hasSuffix(".app") }.map { name -> CleanItem in
            let u = apps.appendingPathComponent(name)
            return CleanItem(url: u, size: FileSizer.size(of: u), modified: FileSizer.modified(u), detail: "/Applications")
        }
        return CleanGroup(id: "macInstallers", title: "macOS yükleyicileri", icon: "apple.logo",
                          note: "Eski macOS kurulum uygulamaları. Gerekirse App Store'dan tekrar indirilebilir.", items: items)
    }

    static func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.path, with: "~")
    }
}
