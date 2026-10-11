import AppKit
import Foundation

/// Sistem çöpünü bulur: önbellekler, loglar, geçici dosyalar, geliştirici artıkları, yarım indirmeler, Çöp Kutusu.
enum JunkScanner {
    private static let home = SafetyGuard.home
    private static func h(_ path: String) -> URL { home.appendingPathComponent(path) }

    /// ~/Library/Caches altında tarayıcılara ait klasör adları.
    static let browserCacheNames: [String: String] = [
        "Google": "Google Chrome", "com.google.Chrome": "Google Chrome",
        "BraveSoftware": "Brave", "com.brave.Browser": "Brave",
        "com.apple.Safari": "Safari", "Firefox": "Firefox", "org.mozilla.firefox": "Firefox",
        "Arc": "Arc", "company.thebrowser.Browser": "Arc",
        "Microsoft Edge": "Microsoft Edge", "com.microsoft.edgemac": "Microsoft Edge",
        "com.operasoftware.Opera": "Opera", "Opera": "Opera",
    ]

    /// ~/Library/Caches altında geliştirici araçlarına ait klasör adları.
    static let devCacheNames: [String: String] = [
        "Homebrew": "Homebrew", "Yarn": "Yarn", "pip": "pip", "pypoetry": "Poetry", "CocoaPods": "CocoaPods",
        "go-build": "Go", "node-gyp": "node-gyp", "typescript": "TypeScript", "ms-playwright": "Playwright",
        "JetBrains": "JetBrains", "org.swift.swiftpm": "SwiftPM", "com.apple.dt.Xcode": "Xcode",
    ]

    /// Silinmesi kullanıcı verisi kaybettirebilecek önbellekler.
    static let cautionCaches: [String: String] = [
        "com.spotify.client": "Çevrimdışı şarkılar silinir",
        "com.apple.Music": "İndirilen müzikler etkilenebilir",
        "com.apple.podcasts": "İndirilen bölümler silinir",
    ]

    static func scan() -> ScanResult {
        if Demo.isOn { return Demo.junk }
        let running = runningBundleIDs()
        // Tam Disk Erişimi olmadan okunamayan yollar
        let denied = [TrashService.trashPath, h("Library/Caches/com.apple.Safari").path]
            .filter { FileSizer.exists(URL(fileURLWithPath: $0)) && !FileSizer.isReadable(URL(fileURLWithPath: $0)) }

        // Grupları paralel tara.
        let tasks: [() -> CleanGroup?] = [
            { userCaches(running: running) },
            { browserCaches(running: running) },
            { logs() },
            { tempFiles() },
            { xcode() },
            { devCaches() },
            { brokenDownloads() },
            { trash() },
        ]
        var groups = [CleanGroup?](repeating: nil, count: tasks.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: tasks.count) { i in
            let g = tasks[i]()
            lock.lock(); groups[i] = g; lock.unlock()
        }
        return ScanResult(groups: groups.compactMap { $0 }.filter { !$0.items.isEmpty }, deniedPaths: denied)
    }

    // MARK: - Gruplar

    private static func userCaches(running: [String: String]) -> CleanGroup {
        let dir = h("Library/Caches")
        let skip = Set(browserCacheNames.keys).union(devCacheNames.keys).union(SafetyGuard.protectedCacheNames)
        let items = FileSizer.children(of: dir, minSize: 1024 * 50)
            .filter { !skip.contains($0.url.lastPathComponent) && !AppPaths.isOwn($0.url.lastPathComponent) }
            .map { item -> CleanItem in
                var i = item
                let name = item.url.lastPathComponent
                if let app = running[name] {
                    i.name = app
                    i.detail = name
                    i.caution = "Uygulama açık"
                } else if let app = appName(forBundleID: name) {
                    i.name = app
                    i.detail = name
                }
                if let c = cautionCaches[name] { i.caution = c }
                return i
            }
        return CleanGroup(id: "userCaches", title: "Kullanıcı önbellekleri", icon: "archivebox",
                          note: "Uygulamaların geçici verileri. Silinirse gerektiğinde yeniden oluşturulur.", items: items)
    }

    private static func browserCaches(running: [String: String]) -> CleanGroup {
        var items: [CleanItem] = []
        let cachesDir = h("Library/Caches")
        for (folder, browser) in browserCacheNames {
            let u = cachesDir.appendingPathComponent(folder)
            guard FileSizer.exists(u) else { continue }
            let s = FileSizer.size(of: u)
            guard s > 0 else { continue }
            items.append(CleanItem(url: u, name: browser, size: s, modified: FileSizer.modified(u), detail: "Önbellek · \(folder)",
                                   caution: isBrowserRunning(browser) ? "Tarayıcı açık" : nil))
        }
        // Chromium tabanlı tarayıcıların profil içi önbellekleri
        let chromium: [(String, String)] = [
            ("Library/Application Support/Google/Chrome", "Google Chrome"),
            ("Library/Application Support/BraveSoftware/Brave-Browser", "Brave"),
            ("Library/Application Support/Microsoft Edge", "Microsoft Edge"),
            ("Library/Application Support/Arc/User Data", "Arc"),
        ]
        for (base, browser) in chromium {
            let baseURL = h(base)
            guard let profiles = try? FileManager.default.contentsOfDirectory(atPath: baseURL.path) else { continue }
            for p in profiles where p == "Default" || p.hasPrefix("Profile ") {
                for sub in ["Code Cache", "GPUCache", "Service Worker/CacheStorage", "DawnGraphiteCache", "DawnWebGPUCache"] {
                    let u = baseURL.appendingPathComponent(p).appendingPathComponent(sub)
                    guard FileSizer.exists(u) else { continue }
                    let s = FileSizer.size(of: u)
                    guard s > 1024 * 100 else { continue }
                    items.append(CleanItem(url: u, name: browser, size: s, modified: FileSizer.modified(u),
                                           detail: "\(p) · \(sub)", caution: isBrowserRunning(browser) ? "Tarayıcı açık" : nil))
                }
            }
        }
        return CleanGroup(id: "browser", title: "Tarayıcı önbellekleri", icon: "globe",
                          note: "Web sayfası önbellekleri. Geçmiş, şifreler ve çerezler silinmez.",
                          items: items.sorted { $0.size > $1.size })
    }

    private static func logs() -> CleanGroup {
        let items = FileSizer.children(of: h("Library/Logs"), minSize: 1024)
            .filter { !["Cleaner", "MacHealth"].contains($0.url.lastPathComponent) }
        return CleanGroup(id: "logs", title: "Log dosyaları", icon: "doc.text",
                          note: "Uygulama ve çökme kayıtları. Sorun gidermiyorsan güvenle silinebilir.", items: items)
    }

    private static func tempFiles() -> CleanGroup {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
        let items = FileSizer.children(of: tmp, minSize: 1024)
            .filter { ($0.modified ?? .distantPast) < cutoff }
        return CleanGroup(id: "temp", title: "Geçici dosyalar", icon: "clock.badge.xmark",
                          note: "3 günden eski geçici dosyalar. Yenileri kullanımda olabileceği için atlanır.", items: items)
    }

    private static func xcode() -> CleanGroup {
        var items: [CleanItem] = []
        let entries: [(String, String, String?)] = [
            ("Library/Developer/Xcode/DerivedData", "DerivedData", nil),
            ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport", nil),
            ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS DeviceSupport", nil),
            ("Library/Developer/CoreSimulator/Caches", "Simülatör önbellekleri", nil),
            ("Library/Developer/Xcode/Archives", "Arşivler", "Yayınlanmış uygulama arşivleri"),
        ]
        for (path, name, caution) in entries {
            let u = h(path)
            guard FileSizer.exists(u) else { continue }
            let s = FileSizer.size(of: u)
            guard s > 0 else { continue }
            items.append(CleanItem(url: u, name: name, size: s, modified: FileSizer.modified(u), detail: path, caution: caution))
        }
        return CleanGroup(id: "xcode", title: "Xcode artıkları", icon: "hammer",
                          note: "Derleme ara dosyaları ve cihaz destek dosyaları. Xcode gerekirse yeniden üretir.", items: items)
    }

    private static func devCaches() -> CleanGroup {
        var items: [CleanItem] = []
        let cachesDir = h("Library/Caches")
        for (folder, tool) in devCacheNames {
            let u = cachesDir.appendingPathComponent(folder)
            guard FileSizer.exists(u) else { continue }
            let s = FileSizer.size(of: u)
            if s > 0 { items.append(CleanItem(url: u, name: tool, size: s, modified: FileSizer.modified(u), detail: "~/Library/Caches/\(folder)")) }
        }
        let others: [(String, String)] = [
            (".npm/_cacache", "npm"), (".gradle/caches", "Gradle"), (".cache/pip", "pip"),
            ("Library/pnpm/store", "pnpm"), (".cargo/registry/cache", "Cargo"), (".m2/repository", "Maven"),
            (".bun/install/cache", "Bun"), (".cache/huggingface", "Hugging Face"),
        ]
        for (path, tool) in others {
            let u = h(path)
            guard FileSizer.exists(u) else { continue }
            let s = FileSizer.size(of: u)
            let risky = tool == "Maven" || tool == "Hugging Face" ? "Tekrar indirilmesi uzun sürebilir" : nil
            if s > 0 { items.append(CleanItem(url: u, name: tool, size: s, modified: FileSizer.modified(u), detail: "~/\(path)", caution: risky)) }
        }
        return CleanGroup(id: "dev", title: "Geliştirici önbellekleri", icon: "terminal",
                          note: "Paket yöneticisi önbellekleri. Silinirse paketler bir sonraki kurulumda yeniden indirilir.",
                          items: items.sorted { $0.size > $1.size })
    }

    private static func brokenDownloads() -> CleanGroup {
        let exts: Set<String> = ["crdownload", "part", "download", "partial", "opdownload"]
        let dir = h("Downloads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let items = names.compactMap { name -> CleanItem? in
            let u = dir.appendingPathComponent(name)
            guard exts.contains(u.pathExtension.lowercased()) else { return nil }
            return CleanItem(url: u, size: FileSizer.size(of: u), modified: FileSizer.modified(u))
        }
        return CleanGroup(id: "broken", title: "Yarım kalmış indirmeler", icon: "arrow.down.circle.dotted",
                          note: "Tamamlanmamış tarayıcı indirmeleri.", items: items)
    }

    private static func trash() -> CleanGroup {
        let dir = URL(fileURLWithPath: TrashService.trashPath)
        let items = FileSizer.children(of: dir)
        return CleanGroup(id: "trash", title: "Çöp Kutusu", icon: "trash",
                          note: "Çöp Kutusu'ndakiler kalıcı olarak silinir, geri alınamaz.", items: items, selectedByDefault: false)
    }

    // MARK: - Yardımcılar

    /// Çalışan uygulamaların bundle id → isim eşlemesi.
    static func runningBundleIDs() -> [String: String] {
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { map[id] = app.localizedName ?? id }
        }
        return map
    }

    private static func isBrowserRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }
    }

    private static func appName(forBundleID id: String) -> String? {
        guard id.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
