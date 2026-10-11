import AppKit
import Foundation

/// Tanıtım görselleri için demo modu (`--demo`): veri kaynakları gerçek Mac yerine uydurma ama gerçekçi
/// veriler döndürür; kullanıcının dosyaları, uygulamaları veya donanım bilgisi hiçbir ekranda görünmez.
/// Uygulama ve klasör ikonları için her Mac'te bulunan Apple uygulamaları ve standart klasörler kullanılır.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    private static let GB: Int64 = 1_073_741_824
    private static let MB: Int64 = 1_048_576
    private static func gb(_ v: Double) -> Int64 { Int64(v * Double(GB)) }
    private static func mb(_ v: Double) -> Int64 { Int64(v * Double(MB)) }
    private static func daysAgo(_ d: Double) -> Date { Date().addingTimeInterval(-d * 86400) }
    private static let home = SafetyGuard.home
    private static func h(_ p: String) -> URL { home.appendingPathComponent(p) }

    // MARK: - Sistem

    static let disk = DiskStats(total: gb(460.4), available: gb(171.6))

    static let memory = MemoryStats(total: 16 * GB, app: gb(6.4), wired: gb(2.1), compressed: gb(0.9), cached: gb(3.8),
                                    free: gb(2.8), swapUsed: 0, swapTotal: 0, pressure: .normal)

    private static let processTable: [(name: String, path: String, cpu: Double, mem: Double)] = [
        ("Safari", "/Applications/Safari.app", 14, 1210),
        ("Photos", "/System/Applications/Photos.app", 9, 845),
        ("Music", "/System/Applications/Music.app", 6, 412),
        ("Mail", "/System/Applications/Mail.app", 3, 388),
        ("Notes", "/System/Applications/Notes.app", 1, 236),
        ("Preview", "/System/Applications/Preview.app", 0.5, 198),
        ("Messages", "/System/Applications/Messages.app", 1.5, 176),
        ("Calendar", "/System/Applications/Calendar.app", 0.3, 142),
        ("Freeform", "/System/Applications/Freeform.app", 0.8, 131),
        ("Maps", "/System/Applications/Maps.app", 0.4, 118),
        ("Weather", "/System/Applications/Weather.app", 0.2, 96),
        ("Podcasts", "/System/Applications/Podcasts.app", 0.2, 88),
    ]

    static var processes: [ProcessInfoRow] {
        processTable.enumerated().map { i, p in
            ProcessInfoRow(pid: Int32(90_000 + i), name: p.name, path: p.path, cpu: p.cpu, memory: mb(p.mem))
        }
    }

    @MainActor static func processIcon(_ pid: Int32) -> NSImage? {
        let i = Int(pid) - 90_000
        guard processTable.indices.contains(i) else { return nil }
        return NSWorkspace.shared.icon(forFile: processTable[i].path)
    }

    static let uptime: TimeInterval = 3 * 86400

    /// Bellek grafiği için son iki dakikalık örnek kullanım (0…1).
    static var memoryHistory: [Double] {
        (0..<59).map { i -> Double in
            let t = Double(i)
            let slow: Double = 0.05 * sin(t / 6)
            let fast: Double = 0.02 * sin(t / 1.7)
            return 0.56 + slow + fast
        }
    }

    // MARK: - Pil ve güvenlik

    static let battery = BatteryInfo(cycleCount: 212, designCycles: 1000, health: 0.94, designCapacity: 4563, fullCapacity: 4289,
                                     charge: 86, isCharging: true, pluggedIn: true, temperature: 29.4, minutesRemaining: nil,
                                     adapterWatts: 35, permanentFailure: false)

    static var batteryHistory: [BatteryHistory.Point] {
        let values: [(Double, Int)] = [(1.0, 18), (0.99, 41), (0.99, 63), (0.98, 88), (0.97, 112), (0.97, 135),
                                       (0.96, 151), (0.96, 170), (0.95, 186), (0.95, 199), (0.94, 212)]
        return values.enumerated().map { i, v in
            BatteryHistory.Point(date: daysAgo(Double(values.count - 1 - i) * 30), health: v.0, cycles: v.1)
        }
    }

    static let security = SecurityStatus(fileVault: true, firewall: true, sip: true, gatekeeper: true, autoUpdates: true,
                                         smart: "Verified", lowPowerMode: false)

    // MARK: - Başlangıç öğeleri

    static var startup: [StartupItem] {
        let rows: [(String, String, StartupItem.Scope, Bool, String)] = [
            ("com.google.keystone.agent", "/Library/Google/GoogleSoftwareUpdate/GoogleUpdater", .allUsers, true, "Google Chrome"),
            ("us.zoom.updater", "/Library/Application Support/zoom.us/ZoomUpdater", .allUsers, true, "Zoom"),
            ("com.dropbox.DropboxMacUpdate.agent", "/Library/DropboxHelperTools/DropboxMacUpdate", .user, false, "Dropbox"),
            ("com.adobe.ARMDCHelper", "/Library/PrivilegedHelperTools/com.adobe.ARMDCHelper", .system, true, "Adobe Acrobat"),
            ("com.spotify.webhelper", "/Applications/Spotify.app/Contents/MacOS/SpotifyWebHelper", .user, false, "Spotify"),
        ]
        return rows.map { label, program, scope, enabled, owner in
            StartupItem(plist: URL(fileURLWithPath: "/Library/LaunchAgents/\(label).plist"), label: label, program: program,
                        scope: scope, enabled: enabled, ownerApp: owner)
        }
    }

    // MARK: - Taramalar

    private static func item(_ path: String, _ size: Int64, days: Double = 20, name: String? = nil, detail: String? = nil,
                             caution: String? = nil) -> CleanItem {
        CleanItem(url: h(path), name: name, size: size, modified: daysAgo(days), detail: detail, caution: caution)
    }

    static var junk: ScanResult {
        ScanResult(groups: [
            CleanGroup(id: "userCaches", title: "Kullanıcı önbellekleri", icon: "archivebox",
                       note: "Uygulamaların geçici verileri. Silinirse gerektiğinde yeniden oluşturulur.", items: [
                           item("Library/Caches/com.spotify.client", mb(1840)),
                           item("Library/Caches/com.apple.Music", mb(926)),
                           item("Library/Caches/com.tinyspeck.slackmacgap", mb(612)),
                           item("Library/Caches/us.zoom.xos", mb(388)),
                           item("Library/Caches/com.figma.Desktop", mb(274)),
                           item("Library/Caches/com.apple.Photos", mb(198)),
                       ]),
            CleanGroup(id: "browser", title: "Tarayıcı önbellekleri", icon: "globe",
                       note: "Web sayfası önbellekleri. Geçmiş, şifreler ve çerezler silinmez.", items: [
                           item("Library/Caches/com.apple.Safari", mb(1460), name: "Safari"),
                           item("Library/Caches/Google/Chrome", mb(2210), name: "Google Chrome"),
                       ], selectedByDefault: false),
            CleanGroup(id: "logs", title: "Log dosyaları", icon: "doc.text",
                       note: "Uygulama ve çökme kayıtları. Sorun gidermiyorsan güvenle silinebilir.", items: [
                           item("Library/Logs/DiagnosticReports", mb(212)),
                           item("Library/Logs/zoom.us", mb(46)),
                       ]),
            CleanGroup(id: "temp", title: "Geçici dosyalar", icon: "clock.badge.xmark",
                       note: "3 günden eski geçici dosyalar. Yenileri kullanımda olabileceği için atlanır.", items: [
                           item("Library/Caches/TemporaryItems", mb(334)),
                       ]),
            CleanGroup(id: "xcode", title: "Xcode artıkları", icon: "hammer",
                       note: "Derleme ara dosyaları ve cihaz destek dosyaları. Xcode gerekirse yeniden üretir.", items: [
                           item("Library/Developer/Xcode/DerivedData", gb(6.8), name: "DerivedData"),
                           item("Library/Developer/Xcode/iOS DeviceSupport", gb(3.9), name: "iOS DeviceSupport"),
                       ]),
            CleanGroup(id: "dev", title: "Geliştirici önbellekleri", icon: "terminal",
                       note: "Paket yöneticisi önbellekleri. Silinirse paketler bir sonraki kurulumda yeniden indirilir.", items: [
                           item(".npm/_cacache", gb(2.4), name: "npm"),
                           item("Library/Caches/Homebrew", gb(1.3), name: "Homebrew"),
                           item("Library/Caches/pip", mb(540), name: "pip"),
                       ]),
        ], deniedPaths: [])
    }

    static var largeFiles: ScanResult {
        ScanResult(groups: [
            CleanGroup(id: "large", title: "Büyük dosyalar", icon: "doc.badge.ellipsis",
                       note: "100 MB üzerindeki dosyalar. Kişisel dosyaların olabilir, dikkatle seç.", items: [
                           item("Movies/Tatil 2025.mov", gb(4.6), days: 210),
                           item("Movies/Sunum kaydı.mp4", gb(2.1), days: 140),
                           item("Documents/Proje arşivi.zip", gb(1.7), days: 320),
                           item("Desktop/Ekran kaydı 2026-03-02.mov", mb(980), days: 190),
                       ], selectedByDefault: false),
            CleanGroup(id: "installers", title: "Kurulum dosyaları", icon: "shippingbox",
                       note: "İndirilenler'deki .dmg / .pkg dosyaları. Uygulama kurulduysa artık gerekmez.", items: [
                           item("Downloads/Figma.dmg", mb(412), days: 60),
                           item("Downloads/zoomusInstallerFull.pkg", mb(186), days: 95),
                           item("Downloads/GoogleChrome.dmg", mb(224), days: 120),
                       ]),
            CleanGroup(id: "iosBackups", title: "iPhone / iPad yedekleri", icon: "iphone",
                       note: "Finder ile alınmış yerel yedekler. iCloud yedeklerini etkilemez.", items: [
                           item("Library/Application Support/MobileSync/Backup/iPhone", gb(8.3), days: 400, name: "iPhone yedeği"),
                       ], selectedByDefault: false),
        ], deniedPaths: [])
    }

    static var folders: ScanResult {
        ScanResult(groups: [
            CleanGroup(id: "devFolders", title: "Geliştirici klasörleri", icon: "shippingbox",
                       note: "Projelerdeki node_modules, .venv, Pods gibi yeniden kurulabilen klasörler. Aktif projeler seçilmez.", items: [
                           item("Developer/web-site/node_modules", mb(820), days: 120, name: "web-site › node_modules"),
                           item("Developer/ml-deneme/.venv", mb(1420), days: 200, name: "ml-deneme › .venv"),
                           item("Developer/ios-uygulama/Pods", mb(640), days: 90, name: "ios-uygulama › Pods"),
                       ]),
            CleanGroup(id: "emptyFolders", title: "Boş klasörler", icon: "folder",
                       note: "İçinde hiçbir dosya olmayan klasörler.", items: [
                           item("Documents/Yeni Klasör", 4096, days: 300),
                           item("Downloads/Arşiv", 4096, days: 250),
                       ]),
        ], deniedPaths: [])
    }

    static var duplicates: ScanResult {
        func group(_ name: String, _ size: Int64, _ paths: [String]) -> CleanGroup {
            let items = paths.map { item($0, size) }
            return CleanGroup(id: "dup-" + paths[0], title: name, icon: "photo", note: "\(paths.count) kopya",
                              items: items, preselected: Set(items.dropFirst().map(\.url)), insightKey: "duplicates")
        }
        return ScanResult(groups: [
            group("IMG_2041.HEIC", mb(4.2), ["Pictures/IMG_2041.HEIC", "Downloads/IMG_2041.HEIC"]),
            group("Sunum.key", mb(86), ["Documents/Sunum.key", "Desktop/Sunum.key"]),
        ], deniedPaths: [])
    }

    // MARK: - Uygulamalar

    private static let appTable: [(name: String, path: String, id: String, genre: String, size: Double, data: Double, used: Double?, added: Double)] = [
        ("TV", "/System/Applications/TV.app", "com.apple.TV", "Eğlence", 0.21, 6.4, 240, 600),
        ("Music", "/System/Applications/Music.app", "com.apple.Music", "Müzik", 0.19, 2.6, 2, 600),
        ("Podcasts", "/System/Applications/Podcasts.app", "com.apple.podcasts", "Eğlence", 0.12, 1.9, 410, 600),
        ("Photo Booth", "/System/Applications/Photo Booth.app", "com.apple.PhotoBooth", "Fotoğraf", 0.04, 0.6, nil, 600),
        ("Chess", "/System/Applications/Chess.app", "com.apple.Chess", "Oyun", 0.03, 0.01, 520, 600),
        ("Stocks", "/System/Applications/Stocks.app", "com.apple.stocks", "Finans", 0.05, 0.08, 300, 600),
        ("Freeform", "/System/Applications/Freeform.app", "com.apple.freeform", "Üretkenlik", 0.16, 0.42, 6, 400),
        ("Books", "/System/Applications/Books.app", "com.apple.iBooksX", "Başvuru", 0.09, 1.2, 75, 600),
        ("Maps", "/System/Applications/Maps.app", "com.apple.Maps", "Seyahat", 0.11, 0.35, 12, 600),
        ("News", "/System/Applications/News.app", "com.apple.news", "Haber", 0.08, 0.27, 95, 600),
        ("Weather", "/System/Applications/Weather.app", "com.apple.weather", "Hava durumu", 0.06, 0.05, 1, 600),
        ("Journal", "/System/Applications/Journal.app", "com.apple.journal", "Yaşam", 0.04, 0.09, 33, 300),
    ]

    static var apps: [AppInfo] {
        appTable.map { a in
            AppInfo(url: URL(fileURLWithPath: a.path), name: a.name, bundleID: a.id, version: "2.4", size: gb(a.size),
                    lastUsed: a.used.map(daysAgo), dateAdded: daysAgo(a.added), genre: a.genre, isProtected: false,
                    dataSize: gb(a.data))
        }
    }

    static func leftovers(for app: AppInfo) -> [CleanItem] {
        guard let id = app.bundleID, let a = appTable.first(where: { $0.id == id }) else { return [] }
        let data = gb(a.data)
        return [
            item("Library/Containers/\(id)", Int64(Double(data) * 0.82), detail: "~/Library/Containers", caution: "Kişisel veri olabilir"),
            item("Library/Caches/\(id)", Int64(Double(data) * 0.15), detail: "~/Library/Caches"),
            item("Library/Application Support/\(id)", Int64(Double(data) * 0.03), detail: "~/Library/Application Support"),
            item("Library/Preferences/\(id).plist", 12_288, detail: "~/Library/Preferences"),
            item("Library/Saved Application State/\(id).savedState", 86_016, detail: "~/Library/Saved Application State"),
        ]
    }

    static var orphans: [CleanItem] {
        [
            item("Library/Application Support/com.example.VideoConverter", mb(1240), days: 380, name: "com.example.VideoConverter",
                 detail: "~/Library/Application Support"),
            item("Library/Caches/com.example.PhotoEditor", mb(312), days: 260, name: "com.example.PhotoEditor", detail: "~/Library/Caches"),
            item("Library/Preferences/com.example.Notes2.plist", 8192, days: 500, name: "com.example.Notes2", detail: "~/Library/Preferences"),
        ]
    }

    static var spaceHogs: [SpaceHog] {
        [
            SpaceHog(id: "pictures", title: "Resimler", detail: "Fotoğraflar kütüphanesi dahil", icon: "photo", size: gb(38.2), kind: .folder(h("Pictures"))),
            SpaceHog(id: "movies", title: "Filmler", detail: "Videolar ve ekran kayıtları", icon: "film", size: gb(24.7), kind: .folder(h("Movies"))),
            SpaceHog(id: "xcode", title: "Xcode ve simülatörler", detail: "Derleme dosyaları ve simülatörler", icon: "hammer", size: gb(19.4), kind: .folder(h("Library/Developer"))),
            SpaceHog(id: "documents", title: "Belgeler", detail: "Belgeler klasörü", icon: "doc", size: gb(14.9), kind: .folder(h("Documents"))),
            SpaceHog(id: "app-tv", title: "TV verileri", detail: "İndirilen film ve diziler", icon: "app.badge", size: gb(6.4), kind: .app(URL(fileURLWithPath: "/System/Applications/TV.app"))),
            SpaceHog(id: "downloads", title: "İndirilenler", detail: "İndirilen dosyalar", icon: "arrow.down.circle", size: gb(5.8), kind: .folder(h("Downloads"))),
        ]
    }

    // MARK: - Disk Haritası (ana klasör)

    static var homeMap: (items: [CleanItem], dirs: Set<URL>) {
        let rows: [(String, Double)] = [("Library", 52.6), ("Pictures", 38.2), ("Movies", 24.7), ("Documents", 14.9), ("Desktop", 9.3),
                                        ("Downloads", 5.8), ("Music", 4.1), ("Public", 0.01)]
        let items = rows.map { CleanItem(url: h($0.0), size: gb($0.1), modified: daysAgo(2)) }
        return (items, Set(items.map(\.url)))
    }

    // MARK: - Geçmiş

    static var history: [CleanupRecord] {
        [
            CleanupRecord(date: daysAgo(3), module: Module.junk.rawValue,
                          files: [TrashedFile(original: h("Library/Caches/com.spotify.client").path, trashed: nil, size: mb(1840)),
                                  TrashedFile(original: h("Library/Developer/Xcode/DerivedData").path, trashed: nil, size: gb(5.2))]),
            CleanupRecord(date: daysAgo(17), module: Module.uninstaller.rawValue,
                          files: [TrashedFile(original: "/Applications/Ornek.app", trashed: nil, size: mb(780))]),
        ]
    }
}
