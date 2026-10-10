import AppKit
import SwiftUI

/// "Diskini neler dolduruyor?": uygulama verileri ve büyük klasörler tek listede.
struct SpaceHog: Identifiable, Sendable {
    enum Kind: Sendable { case app(URL), folder(URL) }
    let id: String
    let title: String
    let detail: String
    let icon: String
    let size: Int64
    let kind: Kind
}

@MainActor
final class SpaceInsightsModel: ObservableObject {
    @Published var items: [SpaceHog] = []
    @Published var isLoading = false
    @Published var loaded = false

    func load(uninstaller: UninstallerModel) async {
        guard !isLoading else { return }
        isLoading = true
        await uninstaller.load()
        let apps = uninstaller.apps
        let hogs = await Task.detached(priority: .utility) { SpaceInsightsModel.scan(apps: apps) }.value
        withAnimation(.spring(duration: 0.5)) {
            items = hogs
            isLoading = false
            loaded = true
        }
    }

    func invalidate() { loaded = false }

    nonisolated static func scan(apps: [AppInfo]) -> [SpaceHog] {
        let home = SafetyGuard.home
        var out: [SpaceHog] = []

        // Verisi büyük uygulamalar
        for a in apps where a.dataSize > 500 * 1024 * 1024 {
            out.append(SpaceHog(id: "app-" + a.url.path, title: "\(a.name) verileri",
                                detail: Knowledge.appData(bundleID: a.bundleID, name: a.name, dataSize: a.dataSize)?.consequences.first
                                    ?? "Ayarlar, önbellek ve indirilen içerik",
                                icon: "app.badge", size: a.dataSize, kind: .app(a.url)))
        }

        // Bilinen büyük klasörler
        let folders: [(String, String, String, String)] = [
            ("Desktop", "Masaüstü", "Masaüstündeki dosyalar", "menubar.dock.rectangle"),
            ("Documents", "Belgeler", "Belgeler klasörü", "doc"),
            ("Downloads", "İndirilenler", "İndirilen dosyalar", "arrow.down.circle"),
            ("Movies", "Filmler", "Videolar ve ekran kayıtları", "film"),
            ("Pictures", "Resimler", "Fotoğraflar kütüphanesi dahil", "photo"),
            ("Music", "Müzik", "Müzik kütüphanesi", "music.note"),
            ("Library/Android", "Android SDK", "Emülatör imajları ve derleme araçları", "cpu"),
            (".android", "Android emülatörleri", "Sanal cihaz diskleri (AVD)", "iphone"),
            (".gradle", "Gradle önbelleği", "Sistem Çöpü'nden temizlenebilir", "shippingbox"),
            (".npm", "npm önbelleği", "Sistem Çöpü'nden temizlenebilir", "shippingbox"),
            ("Library/Developer", "Xcode ve simülatörler", "Derleme dosyaları ve simülatörler", "hammer"),
            ("Library/Caches", "Uygulama önbellekleri", "Sistem Çöpü'nden güvenle temizlenebilir", "archivebox"),
            ("Library/Application Support/MobileSync", "iPhone yedekleri", "Büyük Dosyalar'dan yönetebilirsin", "iphone"),
        ]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: folders.count) { i in
            let f = folders[i]
            let url = home.appendingPathComponent(f.0)
            guard FileSizer.exists(url) else { return }
            let size = FileSizer.size(of: url)
            guard size > 1024 * 1024 * 1024 else { return }
            let hog = SpaceHog(id: "dir-" + f.0, title: f.1, detail: f.2, icon: f.3, size: size, kind: .folder(url))
            lock.lock(); out.append(hog); lock.unlock()
        }
        return Array(out.sorted { $0.size > $1.size }.prefix(8))
    }
}

struct SpaceInsightsCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: SpaceInsightsModel

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AccentBadge(icon: "chart.pie", size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Diskini neler dolduruyor?").font(.system(size: 15))
                        Text("Uygulama verileri ve büyük klasörler · tıklayınca ayrıntıya gider").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        CircleIconButton(icon: "arrow.clockwise", size: 30, help: "Yeniden hesapla") {
                            Task { await model.load(uninstaller: state.uninstaller) }
                        }
                    }
                }
                if model.items.isEmpty && model.isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12).fill(Theme.pillMuted).frame(height: 34).shimmer()
                    }
                } else {
                    let maxSize = max(model.items.first?.size ?? 1, 1)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], spacing: 6) {
                        ForEach(model.items) { hog in
                            HogRow(hog: hog, fraction: Double(hog.size) / Double(maxSize)) { open(hog) }
                        }
                    }
                }
            }
        }
        .task { if !model.loaded { await model.load(uninstaller: state.uninstaller) } }
    }

    private func open(_ hog: SpaceHog) {
        switch hog.kind {
        case .app(let url):
            if let app = state.uninstaller.apps.first(where: { $0.url == url }) {
                state.uninstaller.tab = .apps
                state.uninstaller.category = nil
                state.uninstaller.select(app)
            }
            state.go(.uninstaller)
        case .folder(let url):
            state.diskMap.show(url)
            state.go(.diskMap)
        }
    }
}

private struct HogRow: View {
    let hog: SpaceHog
    let fraction: Double
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if case .app(let url) = hog.kind {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                    } else {
                        Image(systemName: hog.icon).font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Circle().fill(Theme.accent))
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(hog.title).font(.label(12)).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(hog.size)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }
                    CapsuleBar(fraction: fraction, fill: fraction > 0.6 ? Theme.ink : Theme.accent, track: Theme.surfaceRaised, height: 4)
                    Text(hog.detail).font(.label(9)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Theme.surfaceRaised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}
