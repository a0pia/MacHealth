import Foundation

enum FileSizer {
    static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
    ]

    /// Klasörün diskte kapladığı toplam boyut. Sembolik linkleri takip etmez.
    static func size(of url: URL) -> Int64 { size(of: url, isCancelled: { false }) }

    /// İptal edilebilir sürüm: `isCancelled` true dönerse hesaplamayı yarıda keser.
    static func size(of url: URL, isCancelled: () -> Bool) -> Int64 {
        let values = try? url.resourceValues(forKeys: Set(keys))
        if values?.isSymbolicLink == true { return 0 }
        if values?.isDirectory != true {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        // Tam Disk Erişimi yoksa başka uygulamaların veri kaplarına girme (macOS her biri için ayrı izin sorar).
        if Permissions.shouldAvoid(url) { return 0 }
        let skipContainers = !Permissions.hasFullDiskAccess && Permissions.containsAppContainers(url)
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var n = 0
        for case let child as URL in e {
            n += 1
            if n % 2000 == 0 && isCancelled() { return total }
            if skipContainers && Permissions.isAppContainer(child) { e.skipDescendants(); continue }
            guard let v = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]),
                  v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Klasör okunabilir mi? (Tam Disk Erişimi yoksa bazı yollar okunamaz.)
    static func isReadable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Klasörün doğrudan alt öğelerini, boyutlarıyla birlikte listeler (paralel).
    static func children(of url: URL, minSize: Int64 = 0) -> [CleanItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        let urls = names.filter { $0 != ".DS_Store" }.map { url.appendingPathComponent($0) }
        var results = [CleanItem?](repeating: nil, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let u = urls[i]
            let s = size(of: u)
            guard s >= minSize, s > 0 else { return }
            let item = CleanItem(url: u, size: s, modified: modified(u))
            lock.lock(); results[i] = item; lock.unlock()
        }
        return results.compactMap { $0 }.sorted { $0.size > $1.size }
    }
}
