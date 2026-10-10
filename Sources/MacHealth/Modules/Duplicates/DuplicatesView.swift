import SwiftUI

final class DuplicatesModel: ScanModel {
    init() { super.init(module: .duplicates) }

    override func makeScanner() -> @Sendable () -> ScanResult { { DuplicatesScanner.scan() } }

    /// Boşa giden alan: her gruptan bir kopya hariç.
    override var foundSize: Int64 {
        result.groups.reduce(0) { $0 + $1.items.dropFirst().reduce(0) { $0 + $1.size } }
    }

    /// Bir grubun tüm kopyaları seçilse bile orijinal (ilk öğe) asla silinmez.
    override var selectedItems: [CleanItem] {
        result.groups.flatMap { g -> [CleanItem] in
            let sel = g.items.filter { selection.contains($0.url) }
            if sel.count == g.items.count { return Array(sel.dropFirst()) }
            return sel
        }
    }
}

struct DuplicatesView: View {
    @ObservedObject var model: DuplicatesModel

    var body: some View {
        ScanModuleLayout(
            model: model,
            subtitle: "İçeriği birebir aynı olan dosyalar · her gruptan bir kopya mutlaka korunur",
            emptyIcon: "doc.on.doc",
            emptyTitle: "Kopya dosyaları bul",
            emptyMessage: "Ana klasöründeki 512 KB üzeri dosyaları boyut ve SHA-256 özetiyle karşılaştırır. İsimleri farklı olsa da içeriği aynı olanları bulur.",
            scanningIcon: "doc.on.doc",
            scanningText: "Dosyalar karşılaştırılıyor"
        ) {
            GroupedCleanList(model: model, groupInfo: false)
        }
    }
}
