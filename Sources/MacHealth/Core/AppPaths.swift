import Foundation

/// Uygulamanın veri ve log klasörleri. Eski "Cleaner" adıyla oluşturulmuş klasörleri
/// ilk kullanımda MacHealth'e taşır.
enum AppPaths {
    static let support: URL = migrated(from: "Library/Application Support/Cleaner", to: "Library/Application Support/MacHealth")

    static let logs: URL = {
        let dir = migrated(from: "Library/Logs/Cleaner", to: "Library/Logs/MacHealth")
        let old = dir.appendingPathComponent("cleaner.log"), new = dir.appendingPathComponent("machealth.log")
        if FileManager.default.fileExists(atPath: old.path) && !FileManager.default.fileExists(atPath: new.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        return dir
    }()

    private static func migrated(from old: String, to new: String) -> URL {
        let fm = FileManager.default
        let oldURL = SafetyGuard.home.appendingPathComponent(old)
        let newURL = SafetyGuard.home.appendingPathComponent(new)
        if !fm.fileExists(atPath: newURL.path) && fm.fileExists(atPath: oldURL.path) {
            try? fm.moveItem(at: oldURL, to: newURL)
        }
        try? fm.createDirectory(at: newURL, withIntermediateDirectories: true)
        return newURL
    }

    /// Bu ad MacHealth'in kendi klasörü mü?
    static func isOwn(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("com.a0pia.machealth")
    }
}
