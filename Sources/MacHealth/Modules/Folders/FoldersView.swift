import SwiftUI

final class FoldersModel: ScanModel {
    init() { super.init(module: .folders) }
    override func makeScanner() -> @Sendable () -> ScanResult { { FoldersScanner.scan() } }
}

struct FoldersView: View {
    @ObservedObject var model: FoldersModel

    var body: some View {
        ScanModuleLayout(
            model: model,
            subtitle: "Boş klasörler ve projelerdeki yeniden kurulabilir bağımlılık klasörleri",
            emptyIcon: "folder.badge.minus",
            emptyTitle: "Gereksiz klasörleri bul",
            emptyMessage: "Boş klasörleri ve eski projelerindeki node_modules, .venv, Pods, build gibi klasörleri bulur. Son 14 günde üzerinde çalıştığın projeler otomatik seçilmez.",
            scanningIcon: "folder",
            scanningText: "Klasörler taranıyor"
        ) {
            GroupedCleanList(model: model)
        }
    }
}
