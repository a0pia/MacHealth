import Foundation

/// Temizlenebilir tek bir kalem (dosya veya klasör).
struct CleanItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    var name: String
    var size: Int64
    var modified: Date?
    var detail: String?
    /// Doluysa öğe varsayılan olarak seçilmez ve uyarı gösterilir (ör. "Uygulama açık").
    var caution: String?

    init(url: URL, name: String? = nil, size: Int64, modified: Date? = nil, detail: String? = nil, caution: String? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.modified = modified
        self.detail = detail
        self.caution = caution
    }
}

/// Aynı türden kalemler (ör. "Kullanıcı önbellekleri").
struct CleanGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String
    let note: String
    var items: [CleanItem]
    /// Varsayılan olarak seçili gelsin mi? (Riskli gruplar gelmez.)
    var selectedByDefault: Bool = true
    /// Doluysa varsayılan seçim budur (ör. kopyalarda "biri hariç hepsi").
    var preselected: Set<URL>? = nil
    /// Bilgi kutusu anahtarı (boşsa `id` kullanılır).
    var insightKey: String? = nil

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var insight: Insight? { Knowledge.group(insightKey ?? id) }

    var defaultSelection: Set<URL> {
        if let preselected { return preselected }
        guard selectedByDefault else { return [] }
        return Set(items.filter { $0.caution == nil }.map(\.url))
    }
}

/// Bir tarayıcının ortak sonuç tipi.
struct ScanResult: Sendable {
    var groups: [CleanGroup]
    var deniedPaths: [String]

    var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    var defaultSelection: Set<URL> { groups.reduce(into: []) { $0.formUnion($1.defaultSelection) } }
    var allItems: [CleanItem] { groups.flatMap(\.items) }
    static let empty = ScanResult(groups: [], deniedPaths: [])
}
