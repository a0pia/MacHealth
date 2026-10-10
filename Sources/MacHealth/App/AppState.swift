import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case smartScan, junk, largeFiles, duplicates, folders, uninstaller, health, speedUp, memory, diskMap, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Ana Sayfa"
        case .junk: "Sistem Çöpü"
        case .largeFiles: "Büyük Dosyalar"
        case .duplicates: "Kopya Dosyalar"
        case .folders: "Klasörler"
        case .uninstaller: "Uygulamalar"
        case .health: "Mac Sağlığı"
        case .speedUp: "Hızlandır"
        case .memory: "Bellek"
        case .diskMap: "Disk Haritası"
        case .history: "Geçmiş"
        case .settings: "Ayarlar"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: "Tek tuşla tara ve temizle"
        case .junk: "Önbellek, log, geçici dosyalar"
        case .largeFiles: "Büyük, eski, indirilenler"
        case .duplicates: "Birebir aynı dosyalar"
        case .folders: "Boş ve gereksiz klasörler"
        case .uninstaller: "Kaldır, sıfırla, kategoriler"
        case .health: "Pil, güvenlik, tek tıkla optimize"
        case .speedUp: "Sağlık, başlangıç, bakım"
        case .memory: "RAM ve işlemler"
        case .diskMap: "Yer nereye gidiyor?"
        case .history: "Geri al ve kayıtlar"
        case .settings: "Tercihler ve korumalar"
        }
    }

    var icon: String {
        switch self {
        case .smartScan: "house"
        case .junk: "trash"
        case .largeFiles: "doc.badge.ellipsis"
        case .duplicates: "doc.on.doc"
        case .folders: "folder.badge.minus"
        case .uninstaller: "square.grid.2x2"
        case .health: "heart.text.square"
        case .speedUp: "bolt"
        case .memory: "memorychip"
        case .diskMap: "square.grid.3x3.square"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

    /// Kenar çubuğundaki bölümler.
    static let sections: [(String?, [Module])] = [
        (nil, [.smartScan]),
        ("Temizlik", [.junk, .largeFiles, .duplicates, .folders]),
        ("Uygulamalar", [.uninstaller]),
        ("Performans", [.health, .speedUp, .memory]),
        ("Araçlar", [.diskMap, .history]),
    ]

    /// ⌘1…⌘9 kısayolları için sıra.
    static let shortcutOrder: [Module] = [.smartScan, .junk, .largeFiles, .duplicates, .folders, .uninstaller, .health, .speedUp, .memory]
}

/// Modüller arası paylaşılan durum. Modül modelleri burada tutulur ki sekme değişince sonuçlar kaybolmasın.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var module: Module = .smartScan
    @Published var toast: String?
    @Published var celebration: Int64?
    private var backStack: [Module] = []

    let junk = JunkModel()
    let largeFiles = LargeFilesModel()
    let duplicates = DuplicatesModel()
    let folders = FoldersModel()
    let diskMap = DiskMapModel()
    let uninstaller = UninstallerModel()
    let speedUp = SpeedUpModel()
    let memory = MemoryModel()
    let health = HealthModel()
    let insights = SpaceInsightsModel()

    var canGoBack: Bool { !backStack.isEmpty }

    func go(_ m: Module) {
        guard m != module else { return }
        backStack.append(module)
        if backStack.count > 30 { backStack.removeFirst() }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { module = m }
    }

    func goHome() { go(.smartScan) }

    func back() {
        guard let prev = backStack.popLast() else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { module = prev }
    }

    /// Kenar çubuğunda modülün yanında gösterilecek özet (bulunan boyut vb.).
    func badge(for m: Module) -> String? {
        func size(_ model: ScanModel) -> String? {
            model.hasScanned && model.result.totalSize > 0 ? Format.bytes(model.result.totalSize) : nil
        }
        switch m {
        case .junk: return size(junk)
        case .largeFiles: return size(largeFiles)
        case .duplicates: return size(duplicates)
        case .folders: return size(folders)
        case .uninstaller:
            let n = uninstaller.apps.filter { $0.category == .unneeded }.count
            return n > 0 ? "\(n)" : nil
        case .speedUp: return speedUp.loaded ? "\(speedUp.score)" : nil
        case .health: return health.overall(speed: speedUp).map { "\($0)" }
        default: return nil
        }
    }

    func showToast(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut) { if toast == text { toast = nil } }
        }
    }

    /// Ortak temizlik akışı: Çöp'e taşı → geçmişe ekle → kutlama / bildirim göster.
    func clean(_ items: [CleanItem], module: Module) async -> CleanupOutcome {
        let outcome = await Task.detached(priority: .userInitiated) {
            TrashService.moveToTrash(items, module: module.title)
        }.value
        HistoryStore.shared.add(outcome.record)
        if module != .diskMap { diskMap.invalidateCache() }
        insights.invalidate()
        if outcome.freed > 0 {
            if UserDefaults.standard.bool(forKey: Settings.celebrateKey) {
                celebration = outcome.freed
            } else {
                showToast("\(Format.bytes(outcome.freed)) Çöp Kutusu'na taşındı")
            }
        }
        if !outcome.failed.isEmpty {
            let permission = outcome.failed.contains { $0.reason.localizedCaseInsensitiveContains("izin") || $0.reason.localizedCaseInsensitiveContains("permission") }
            showToast(permission
                      ? "\(outcome.failed.count) öğe macOS tarafından korunuyor · Ayarlar › Tam Disk Erişimi'nden MacHealth'e izin ver"
                      : "\(outcome.failed.count) öğe taşınamadı · ayrıntılar log dosyasında")
        }
        return outcome
    }
}
