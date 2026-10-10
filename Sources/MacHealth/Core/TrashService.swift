import Foundation

struct TrashedFile: Codable, Hashable, Sendable {
    let original: String
    let trashed: String?
    let size: Int64
}

struct CleanupRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let module: String
    var files: [TrashedFile]
    var restored = false

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var canRestore: Bool { !restored && files.contains { $0.trashed != nil } }
}

struct CleanupOutcome: Sendable {
    var record: CleanupRecord
    var failed: [(path: String, reason: String)]
    var freed: Int64 { record.totalSize }
}

/// Dosyaları kalıcı silmek yerine Çöp Kutusu'na taşır ve kayıt tutar.
enum TrashService {
    static let trashPath = SafetyGuard.home.appendingPathComponent(".Trash").path

    static func moveToTrash(_ items: [CleanItem], module: String) -> CleanupOutcome {
        var moved: [TrashedFile] = []
        var failed: [(String, String)] = []

        for item in items {
            guard SafetyGuard.isDeletable(item.url) else {
                failed.append((item.url.path, "Korumalı konum"))
                continue
            }
            guard FileSizer.exists(item.url) else { continue }
            // Zaten Çöp Kutusu'ndaysa (Çöp'ü boşalt) kalıcı silinir.
            if item.url.path.hasPrefix(trashPath + "/") {
                do {
                    try FileManager.default.removeItem(at: item.url)
                    moved.append(TrashedFile(original: item.url.path, trashed: nil, size: item.size))
                } catch {
                    failed.append((item.url.path, error.localizedDescription))
                }
                continue
            }
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
                moved.append(TrashedFile(original: item.url.path, trashed: (resulting as URL?)?.path, size: item.size))
            } catch {
                failed.append((item.url.path, error.localizedDescription))
            }
        }

        let record = CleanupRecord(date: Date(), module: module, files: moved)
        ActivityLog.write(record: record, failed: failed)
        return CleanupOutcome(record: record, failed: failed)
    }

    /// Çöp'e taşınan dosyaları eski yerlerine geri koyar.
    static func restore(_ record: CleanupRecord) -> (restored: Int, failed: Int) {
        var ok = 0, bad = 0
        let fm = FileManager.default
        for file in record.files {
            guard let trashed = file.trashed, fm.fileExists(atPath: trashed),
                  !fm.fileExists(atPath: file.original) else { bad += 1; continue }
            do {
                let parent = (file.original as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: trashed, toPath: file.original)
                ok += 1
            } catch { bad += 1 }
        }
        ActivityLog.append("GERİ ALINDI \(record.module): \(ok) dosya geri yüklendi, \(bad) başarısız")
        return (ok, bad)
    }
}

/// ~/Library/Logs/MacHealth/machealth.log
enum ActivityLog {
    static let url = AppPaths.logs.appendingPathComponent("machealth.log")

    static func append(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(stamp)] \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func write(record: CleanupRecord, failed: [(String, String)]) {
        append("TEMİZLİK \(record.module): \(record.files.count) öğe, \(Format.bytes(record.totalSize))")
        for f in record.files { append("  çöpe → \(f.original) (\(f.size) B)") }
        for f in failed { append("  HATA  \(f.0): \(f.1)") }
    }
}
