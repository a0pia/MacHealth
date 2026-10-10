import AppKit
import SwiftUI

enum Settings {
    static let showMenuBarKey = "showMenuBar"
    static let lowDiskAlertKey = "lowDiskAlert"
    static let lowDiskPercentKey = "lowDiskPercent"
    static let largeFileMinKey = "largeFileMinMB"
    static let ignoredPathsKey = "ignoredPaths"
    static let celebrateKey = "celebrate"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarKey: true,
            lowDiskAlertKey: true,
            lowDiskPercentKey: 10,
            largeFileMinKey: 100,
            celebrateKey: true,
        ])
    }
}

struct SettingsView: View {
    @AppStorage(Settings.showMenuBarKey) private var showMenuBar = true
    @AppStorage(Settings.lowDiskAlertKey) private var lowDiskAlert = true
    @AppStorage(Settings.lowDiskPercentKey) private var lowDiskPercent = 10
    @AppStorage(Settings.largeFileMinKey) private var largeFileMin = 100
    @AppStorage(Settings.celebrateKey) private var celebrate = true
    @State private var ignored: [String] = SafetyGuard.userIgnoreList()

    var body: some View {
        AdaptiveScroll {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    section("Genel", icon: "slider.horizontal.3") {
                        toggleRow("Menü çubuğunda göster", "Disk ve RAM durumu, hızlı temizlik menüsü. Pencere kapansa da çalışmaya devam eder.", $showMenuBar)
                        toggleRow("Temizlik sonrası kutlama", "Temizlik bitince konfetili özet ekranını göster.", $celebrate)
                    }
                    section("Uyarılar", icon: "bell") {
                        toggleRow("Disk dolunca uyar", "Boş alan eşiğin altına inince bildirim gönder.", $lowDiskAlert)
                        HStack {
                            Text("Uyarı eşiği").font(.label(12))
                            Spacer()
                            ForEach([5, 10, 15, 20], id: \.self) { p in
                                PillButton(title: "%\(p)", style: lowDiskPercent == p ? .dark : .muted, compact: true) { lowDiskPercent = p }
                            }
                        }
                        .disabled(!lowDiskAlert).opacity(lowDiskAlert ? 1 : 0.5)
                    }
                    section("Tarama", icon: "magnifyingglass") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Büyük dosya sınırı").font(.label(12))
                                Text("Büyük Dosyalar taramasında varsayılan alt sınır.").font(.label(10)).foregroundStyle(Theme.inkMuted)
                            }
                            Spacer()
                            ForEach([50, 100, 500, 1024], id: \.self) { mb in
                                PillButton(title: mb >= 1024 ? "1 GB" : "\(mb) MB", style: largeFileMin == mb ? .dark : .muted, compact: true) { largeFileMin = mb }
                            }
                        }
                    }
                }

                VStack(spacing: 14) {
                    section("İzinler", icon: "lock.shield") {
                        PermissionsPanel()
                    }
                    section("Dokunma listesi", icon: "hand.raised") {
                        Text("Bu klasörler ve içindekiler hiçbir taramada silinmez.").font(.label(11)).foregroundStyle(Theme.inkMuted)
                        if ignored.isEmpty {
                            Text("Liste boş.").font(.label(12)).foregroundStyle(Theme.inkMuted).padding(.vertical, 6)
                        }
                        ForEach(ignored, id: \.self) { path in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                                Text(path.replacingOccurrences(of: SafetyGuard.home.path, with: "~")).font(.label(12)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                MiniIcon(icon: "xmark", help: "Listeden çıkar") {
                                    ignored.removeAll { $0 == path }
                                    save()
                                }
                            }
                            .padding(.horizontal, 10).frame(height: 38)
                            .background(Capsule().fill(Theme.surfaceRaised))
                        }
                        PillButton(title: "Klasör ekle", icon: "plus", style: .raised, compact: true) { addIgnored() }
                    }
                    section("Hakkında", icon: "info.circle") {
                        HStack(spacing: 14) {
                            LogoMark(size: 56, animated: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("MacHealth").font(.display(22))
                                Text("Sürüm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme")")
                                    .font(.label(11)).foregroundStyle(Theme.inkMuted)
                                Text("Silinen her şey önce Çöp Kutusu'na gider.").font(.label(11)).foregroundStyle(Theme.inkMuted)
                            }
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            PillButton(title: "Log dosyası", icon: "doc.text", style: .raised, compact: true) { SystemActions.revealInFinder(ActivityLog.url) }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(ignored, forKey: Settings.ignoredPathsKey)
    }

    private func addIgnored() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Koru"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !ignored.contains(url.path) { ignored.append(url.path) }
        save()
    }

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AccentBadge(icon: icon, size: 30)
                    Text(title).font(.system(size: 15))
                }
                content()
            }
        }
    }

    private func toggleRow(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.label(12))
                Text(detail).font(.label(10)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding).toggleStyle(.switch).tint(Theme.ink).labelsHidden().controlSize(.small)
        }
    }
}
