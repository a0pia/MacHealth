import SwiftUI

/// Tara → listele → seç → temizle akışının ortak modeli.
@MainActor
class ScanModel: ObservableObject {
    @Published var result: ScanResult = .empty
    @Published var selection: Set<URL> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasScanned = false
    @Published var expanded: Set<String> = []

    let module: Module

    init(module: Module) { self.module = module }

    /// Alt sınıflar, arka planda çalışacak tarama işini burada döndürür.
    func makeScanner() -> @Sendable () -> ScanResult { { .empty } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let scanner = makeScanner()
        let r = await Task.detached(priority: .userInitiated) { scanner() }.value
        withAnimation(.spring(duration: 0.4)) {
            result = r
            selection = r.defaultSelection
            hasScanned = true
            isScanning = false
        }
    }

    var selectedItems: [CleanItem] { result.allItems.filter { selection.contains($0.url) } }
    /// Ekranda "Bulunan" olarak gösterilen boyut.
    var foundSize: Int64 { result.totalSize }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func state(of group: CleanGroup) -> SelectionState {
        let n = group.items.filter { selection.contains($0.url) }.count
        return n == 0 ? .none : (n == group.items.count ? .all : .some)
    }

    func toggle(group: CleanGroup) {
        let urls = Set(group.items.map(\.url))
        if state(of: group) == .all { selection.subtract(urls) } else { selection.formUnion(urls) }
    }

    func toggle(_ item: CleanItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    func clean(using app: AppState) async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isCleaning = true
        let outcome = await app.clean(items, module: module)
        let removed = Set(outcome.record.files.map { URL(fileURLWithPath: $0.original) })
        withAnimation(.spring(duration: 0.4)) {
            for i in result.groups.indices {
                result.groups[i].items.removeAll { removed.contains($0.url) }
            }
            // Kopya gruplarında tek dosya kaldıysa artık kopya değildir.
            result.groups.removeAll { $0.items.isEmpty || ($0.insightKey == "duplicates" && $0.items.count < 2) }
            selection.subtract(removed)
            isCleaning = false
        }
    }
}
