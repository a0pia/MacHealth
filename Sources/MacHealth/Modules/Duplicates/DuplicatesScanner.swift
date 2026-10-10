import CryptoKit
import Foundation

/// İçeriği birebir aynı dosyaları bulur: boyut → kısmi özet → tam SHA-256.
enum DuplicatesScanner {
    private static let home = SafetyGuard.home

    struct Candidate { let url: URL; let size: Int64; let created: Date?; let modified: Date? }

    static func scan(minSize: Int64 = 512 * 1024) -> ScanResult {
        let files = collect(minSize: minSize)

        // 1) Aynı boyuttakiler
        let bySize = Dictionary(grouping: files, by: \.size).values.filter { $0.count > 1 }

        // 2) Kısmi özet (ilk + son 64 KB), 3) tam özet
        var sets: [[Candidate]] = []
        let lock = NSLock()
        let buckets = Array(bySize)
        DispatchQueue.concurrentPerform(iterations: buckets.count) { i in
            let partial = Dictionary(grouping: buckets[i], by: { partialHash($0.url, size: $0.size) ?? UUID().uuidString })
                .values.filter { $0.count > 1 }
            for group in partial {
                let full = Dictionary(grouping: group, by: { fullHash($0.url) ?? UUID().uuidString })
                    .values.filter { $0.count > 1 }
                lock.lock(); sets += full; lock.unlock()
            }
        }

        let groups = sets.map { set -> CleanGroup in
            let keeper = chooseKeeper(set)
            let items = ([keeper] + set.filter { $0.url != keeper.url }).map { c in
                CleanItem(url: c.url, size: c.size, modified: c.modified,
                          detail: LargeFilesScanner.shortPath(c.url.deletingLastPathComponent()),
                          caution: c.url == keeper.url ? "Orijinal · korunur" : nil)
            }
            let name = keeper.url.lastPathComponent
            let wasted: Int64 = keeper.size * Int64(set.count - 1)
            let note: String = "\(set.count) kopya · her biri \(Format.bytes(keeper.size)) · \(Format.bytes(wasted)) boşa"
            return CleanGroup(id: "dup-" + keeper.url.path, title: name, icon: icon(for: keeper.url),
                              note: note, items: items, insightKey: "duplicates")
        }
        .sorted { wasted($0) > wasted($1) }

        return ScanResult(groups: groups, deniedPaths: [])
    }

    private static func wasted(_ g: CleanGroup) -> Int64 {
        let each: Int64 = g.items.first?.size ?? 0
        return each * Int64(g.items.count - 1)
    }

    // MARK: - Dosya toplama

    private static func collect(minSize: Int64) -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isPackageKey, .isDirectoryKey,
                                      .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey]
        let skipNames: Set<String> = ["node_modules", ".git", "Pods", ".venv", "venv", "DerivedData", "build", ".gradle", "target"]
        let tops = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0 != "Library" && !$0.hasPrefix(".") }
            .map { home.appendingPathComponent($0) }

        var out: [Candidate] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: tops.count) { i in
            guard let e = FileManager.default.enumerator(at: tops[i], includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return }
            var local: [Candidate] = []
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isDirectory == true {
                    if v.isPackage == true || skipNames.contains(url.lastPathComponent) { e.skipDescendants() }
                    continue
                }
                guard v.isRegularFile == true, v.isSymbolicLink != true, let s = v.fileSize, Int64(s) >= minSize else { continue }
                local.append(Candidate(url: url, size: Int64(s), created: v.creationDate, modified: v.contentModificationDate))
            }
            lock.lock(); out += local; lock.unlock()
        }
        return out
    }

    // MARK: - Özetler

    private static func partialHash(_ url: URL, size: Int64) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let chunk = 64 * 1024
        var hasher = SHA256()
        if let head = try? h.read(upToCount: chunk) { hasher.update(data: head) }
        if size > Int64(chunk * 2) {
            try? h.seek(toOffset: UInt64(size) - UInt64(chunk))
            if let tail = try? h.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let data = autoreleasepool { try? h.read(upToCount: 1024 * 1024) }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Hangisi korunacak?

    /// İndirilenler dışındakini, sonra en eskisini, sonra en kısa yolu tercih eder.
    private static func chooseKeeper(_ set: [Candidate]) -> Candidate {
        let downloads = home.appendingPathComponent("Downloads").path
        return set.sorted { a, b in
            let ad = a.url.path.hasPrefix(downloads), bd = b.url.path.hasPrefix(downloads)
            if ad != bd { return !ad }
            let ac = a.created ?? .distantFuture, bc = b.created ?? .distantFuture
            if ac != bc { return ac < bc }
            return a.url.path.count < b.url.path.count
        }.first!
    }

    static func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "raw", "cr2", "nef": "photo"
        case "mov", "mp4", "m4v", "avi", "mkv": "film"
        case "mp3", "m4a", "wav", "aac", "flac": "music.note"
        case "pdf": "doc.richtext"
        case "zip", "rar", "7z", "gz", "tar", "dmg", "pkg", "iso": "archivebox"
        case "doc", "docx", "pages", "txt", "rtf", "md": "doc.text"
        case "xls", "xlsx", "numbers", "csv": "tablecells"
        case "ppt", "pptx", "key": "rectangle.on.rectangle"
        default: "doc.on.doc"
        }
    }
}
