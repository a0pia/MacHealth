import Foundation
import SwiftUI

/// Temizlik geçmişi: ~/Library/Application Support/MacHealth/history.json
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var records: [CleanupRecord] = []

    private let url: URL = {
        AppPaths.support.appendingPathComponent("history.json")
    }()

    init() {
        if Demo.isOn { records = Demo.history } else { load() }
    }

    var totalFreed: Int64 { records.filter { !$0.restored }.reduce(0) { $0 + $1.totalSize } }
    var lastRestorable: CleanupRecord? { records.first { $0.canRestore } }

    func add(_ record: CleanupRecord) {
        guard !record.files.isEmpty else { return }
        records.insert(record, at: 0)
        save()
    }

    func restore(_ record: CleanupRecord) -> (restored: Int, failed: Int) {
        let result = TrashService.restore(record)
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i].restored = true
            save()
        }
        return result
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        records = (try? d.decode([CleanupRecord].self, from: data)) ?? []
    }

    private func save() {
        guard !Demo.isOn else { return }   // demo kayıtları gerçek geçmişin üzerine yazılmasın
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(records).write(to: url, options: .atomic)
    }
}
