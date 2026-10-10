import Foundation

/// Asla silinmemesi gereken yolları korur. Tüm silme işlemleri buradan geçer.
enum SafetyGuard {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Bu yolların kendisi asla silinmez.
    private static var protectedExact: Set<String> {
        let h = home.path
        return [
            "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/etc", "/var",
            h, "\(h)/Library", "\(h)/Documents", "\(h)/Desktop", "\(h)/Downloads", "\(h)/Pictures",
            "\(h)/Music", "\(h)/Movies", "\(h)/Applications", "\(h)/Library/Caches", "\(h)/Library/Logs",
            "\(h)/Library/Application Support", "\(h)/Library/Preferences", "\(h)/Library/Containers",
            "\(h)/Public", "\(h)/Public/Drop Box", "\(h)/Sites", "\(h)/Library/Mobile Documents",
        ]
    }

    /// Bu yolların altındaki hiçbir şey silinmez.
    private static var protectedPrefixes: [String] {
        let h = home.path
        return [
            "/System/", "/usr/", "/bin/", "/sbin/",
            "\(h)/Library/Mobile Documents/",          // iCloud Drive
            "\(h)/Library/Keychains/",
            "\(h)/Library/Mail/",
            "\(h)/Library/Messages/",
            "\(h)/Pictures/Photos Library.photoslibrary/",
            "\(h)/Library/CloudStorage/",
        ]
    }

    /// Önbelleği silinmemesi gereken Apple bileşenleri (silmek sorun çıkarabilir).
    static let protectedCacheNames: Set<String> = [
        "com.apple.akd", "com.apple.ap.adprivacyd", "CloudKit", "com.apple.bird", "com.apple.containermanagerd",
        "com.apple.HomeKit", "com.apple.nsurlsessiond", "FamilyCircle", "com.apple.findmy.findmylocateagent",
        "com.apple.iCloudHelper", "com.apple.Safari.SafeBrowsing", "com.apple.trustd", "com.apple.cache_delete",
    ]

    static func userIgnoreList() -> [String] {
        UserDefaults.standard.stringArray(forKey: "ignoredPaths") ?? []
    }

    static func isDeletable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if protectedExact.contains(path) { return false }
        if protectedPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        if userIgnoreList().contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        return true
    }
}
