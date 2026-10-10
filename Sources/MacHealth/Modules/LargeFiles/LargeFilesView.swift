import SwiftUI

final class LargeFilesModel: ScanModel {
    @Published var minSizeMB: Int = UserDefaults.standard.integer(forKey: Settings.largeFileMinKey).nonZero ?? 100

    init() { super.init(module: .largeFiles) }

    override func makeScanner() -> @Sendable () -> ScanResult {
        let options = LargeFilesScanner.Options(minSize: Int64(minSizeMB) * 1024 * 1024)
        return { LargeFilesScanner.scan(options) }
    }
}

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel

    var body: some View {
        ScanModuleLayout(
            model: model,
            subtitle: "Büyük ve uzun süredir açılmamış dosyalar, indirilenler, cihaz yedekleri",
            emptyIcon: "doc.badge.ellipsis",
            emptyTitle: "Yer kaplayan dosyaları bul",
            emptyMessage: "Ana klasörünü tarayarak büyük ve eski dosyaları, kurulum dosyalarını, iPhone yedeklerini ve eski macOS yükleyicilerini listeler.",
            scanningIcon: "doc.badge.ellipsis",
            scanningText: "Dosyalar taranıyor",
            headerAccessory: AnyView(sizePicker)
        ) {
            GroupedCleanList(model: model)
        }
    }

    private var sizePicker: some View {
        HStack(spacing: 4) {
            Text("En az").font(.label(11)).foregroundStyle(Theme.inkMuted).padding(.trailing, 4)
            ForEach([50, 100, 500, 1024], id: \.self) { mb in
                PillButton(title: mb >= 1024 ? "1 GB" : "\(mb) MB", style: model.minSizeMB == mb ? .raised : .muted, compact: true) {
                    guard !model.isScanning else { return }
                    model.minSizeMB = mb
                    if model.hasScanned { Task { await model.scan() } }
                }
                .disabled(model.isScanning)
            }
        }
        .padding(.trailing, 24)
    }
}

extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
