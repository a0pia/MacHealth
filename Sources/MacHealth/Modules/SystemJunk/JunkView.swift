import SwiftUI

final class JunkModel: ScanModel {
    init() { super.init(module: .junk) }
    override func makeScanner() -> @Sendable () -> ScanResult { { JunkScanner.scan() } }
}

struct JunkView: View {
    @ObservedObject var model: JunkModel

    var body: some View {
        ScanModuleLayout(
            model: model,
            subtitle: "Önbellekler, loglar, geçici dosyalar ve geliştirici artıkları",
            emptyIcon: "trash",
            emptyTitle: "Sistem çöpünü bul",
            emptyMessage: "Önbellekleri, logları, geçici dosyaları, Xcode ve paket yöneticisi artıklarını tarar. Hiçbir şey onayın olmadan silinmez.",
            scanningIcon: "trash",
            scanningText: "Sistem çöpü aranıyor"
        ) {
            GroupedCleanList(model: model)
        }
    }
}

/// Tarama tabanlı modüllerin ortak düzeni: başlık + istatistik, liste, alt aksiyon barı.
struct ScanModuleLayout<Content: View>: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: ScanModel
    let subtitle: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    var scanningIcon: String = "sparkle.magnifyingglass"
    let scanningText: String
    var headerAccessory: AnyView? = nil
    @ViewBuilder var content: Content

    @State private var showSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                Text(subtitle).font(.label(12)).foregroundStyle(Theme.inkMuted)
                Spacer()
                if let headerAccessory { headerAccessory }
                if model.hasScanned && !model.isScanning {
                    StatBlock(label: "Bulunan", value: Format.bytesSplit(model.foundSize).0,
                              unit: Format.bytesSplit(model.foundSize).1)
                    StatBlock(label: "Seçilen", value: Format.bytesSplit(model.selectedSize).0,
                              unit: Format.bytesSplit(model.selectedSize).1)
                        .padding(.leading, 18)
                        .animation(.spring(duration: 0.3), value: model.selectedSize)
                    CircleIconButton(icon: "arrow.clockwise", help: "Yeniden tara") { Task { await model.scan() } }
                        .padding(.leading, 12)
                }
            }

            if !model.result.deniedPaths.isEmpty && !model.isScanning { FullDiskAccessBanner() }

            ZStack(alignment: .bottom) {
                if model.isScanning {
                    ScanningPlaceholder(text: scanningText, icon: scanningIcon)
                        .transition(.opacity)
                } else if !model.hasScanned {
                    EmptyStateView(icon: emptyIcon, title: emptyTitle, message: emptyMessage, actionTitle: "Taramayı başlat") {
                        Task { await model.scan() }
                    }
                    .transition(.opacity)
                } else if model.result.groups.isEmpty {
                    EmptyStateView(icon: "checkmark", title: "Her şey temiz", message: "Temizlenecek bir şey bulunamadı.",
                                   actionTitle: "Yeniden tara") { Task { await model.scan() } }
                } else {
                    content
                        .transition(.opacity.combined(with: .offset(y: 20)))
                    BottomActionBar(actionTitle: "Gözden geçir ve temizle", actionIcon: "sparkles",
                                    enabled: !model.selection.isEmpty, busy: model.isCleaning) {
                        HStack(spacing: 10) {
                            BytesText(bytes: model.selectedSize, size: 22)
                            Text("· \(model.selectedItems.count) öğe seçildi").font(.label(12)).foregroundStyle(Theme.inkMuted)
                        }
                    } action: { showSummary = true }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .sheet(isPresented: $showSummary) {
            CleanSummarySheet(title: "Temizlik özeti", lines: CleanSummarySheet.Line.from(model)) {
                Task { await model.clean(using: app) }
            }
        }
    }
}
