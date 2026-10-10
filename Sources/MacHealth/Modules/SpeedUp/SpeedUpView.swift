import AppKit
import SwiftUI

@MainActor
final class SpeedUpModel: ObservableObject {
    @Published var checks: [HealthCheck] = []
    @Published var score: Int = 0
    @Published var startup: [StartupItem] = []
    @Published var heavy: [ProcessInfoRow] = []
    @Published var isLoading = false
    @Published var loaded = false
    @Published var running: Set<String> = []
    @Published var done: Set<String> = []
    @Published var snapshots = 0
    @Published var startupFilter: StartupItem.Scope? = nil

    let tasks = MaintenanceService.tasks

    func load() async {
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { () -> ([StartupItem], [ProcessInfoRow], Int, HealthService.Input) in
            let startup = StartupService.list()
            let procs = SystemInfo.processes().filter { $0.pid != getpid() }.sorted { $0.cpu > $1.cpu }
            let heavy = Array(procs.prefix(8))
            let snaps = MaintenanceService.localSnapshotCount()
            let input = HealthService.Input(
                disk: SystemInfo.disk(), memory: SystemInfo.memory(),
                enabledStartupCount: startup.filter(\.enabled).count, heavyProcesses: heavy,
                uptime: SystemInfo.uptime, thermal: SystemInfo.thermalState, snapshots: snaps)
            return (startup, heavy, snaps, input)
        }.value
        let checks = HealthService.evaluate(result.3)
        withAnimation(.spring(duration: 0.5)) {
            startup = result.0
            heavy = result.1
            snapshots = result.2
            self.checks = checks
            score = HealthService.score(checks)
            isLoading = false
            loaded = true
        }
    }

    var visibleStartup: [StartupItem] {
        guard let f = startupFilter else { return startup }
        return startup.filter { $0.scope == f }
    }

    func toggle(_ item: StartupItem, using state: AppState) {
        let target = !item.enabled
        running.insert(item.id)
        Task {
            let out = await Task.detached { StartupService.setEnabled(item, target) }.value
            running.remove(item.id)
            if out.ok, let i = startup.firstIndex(of: item) {
                startup[i].enabled = target
                ActivityLog.append("BAŞLANGIÇ \(item.label) → \(target ? "etkin" : "devre dışı")")
                if !target && item.insight.risk == .caution, let app = item.ownerApp {
                    state.showToast("\(item.displayName) kapatıldı · \(app) düzgün çalışmayabilir")
                } else {
                    state.showToast("\(item.displayName) \(target ? "etkinleştirildi" : "devre dışı bırakıldı")")
                }
            } else if !out.stderr.contains("-128") {
                state.showToast("Değiştirilemedi: \(out.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))")
            }
        }
    }

    func run(_ task: MaintenanceTask, using state: AppState) {
        running.insert(task.id)
        Task {
            let out = await Task.detached { task.run() }.value
            running.remove(task.id)
            if out.ok {
                done.insert(task.id)
                ActivityLog.append("BAKIM \(task.title): tamam")
                state.showToast("\(task.title) · tamamlandı")
                if task.id == "snapshots" { snapshots = 0 }
            } else if !out.stderr.contains("-128") {   // -128: kullanıcı şifre penceresini kapattı
                ActivityLog.append("BAKIM \(task.title): HATA \(out.stderr)")
                state.showToast("\(task.title) başarısız oldu")
            }
        }
    }
}

struct SpeedUpView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: SpeedUpModel
    @State private var pendingQuit: ProcessInfoRow?
    @State private var confirmRestart = false

    var body: some View {
        // Geniş pencerede iki sütun, dar pencerede tek sütun.
        GeometryReader { geo in
            AdaptiveScroll {
                VStack(spacing: 14) {
                    health
                    if geo.size.width >= 1080 {
                        HStack(alignment: .top, spacing: 14) {
                            startupCard
                            VStack(spacing: 14) {
                                maintenanceCard
                                heavyCard
                            }
                            .frame(width: min(430, geo.size.width * 0.4))
                        }
                    } else {
                        VStack(spacing: 14) {
                            startupCard
                            HStack(alignment: .top, spacing: 14) {
                                maintenanceCard
                                heavyCard
                            }
                        }
                    }
                }
                .frame(width: geo.size.width)
                .padding(.bottom, 10)
            }
        }
        .task { if !model.loaded { await model.load() } }
        .confirmationDialog("\(pendingQuit?.name ?? "") kapatılsın mı?", isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })) {
            if let p = pendingQuit {
                Button("Kapat") { state.memory.quit(p, force: false, using: state); Task { try? await Task.sleep(for: .seconds(1.5)); await model.load() } }
                Button("Zorla kapat", role: .destructive) { state.memory.quit(p, force: true, using: state); Task { try? await Task.sleep(for: .seconds(1.5)); await model.load() } }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Mac yeniden başlatılsın mı?", isPresented: $confirmRestart) {
            Button("Yeniden başlat", role: .destructive) {
                Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Açık uygulamalar kapatılacak. Kaydedilmemiş işlerini önce kaydet.")
        }
    }

    // MARK: - Sağlık

    private var health: some View {
        Card(padding: 22) {
            HStack(alignment: .top, spacing: 28) {
                ZStack {
                    RingGauge(fraction: Double(model.score) / 100, lineWidth: 14,
                              color: model.score >= 80 ? Theme.accent : (model.score >= 55 ? Color(hex: 0xF7C948) : Theme.danger))
                    VStack(spacing: 0) {
                        Text(model.loaded ? "\(model.score)" : "–").font(.display(40)).contentTransition(.numericText())
                        Text("Mac sağlığı").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(summary).font(.display(22))
                        Spacer()
                        CircleIconButton(icon: "arrow.clockwise", size: 34, help: "Yeniden kontrol et") { Task { await model.load() } }
                    }
                    if model.isLoading && !model.loaded {
                        ProgressView().controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                        ForEach(model.checks) { check in CheckRow(check: check) { handle(check.fix) } }
                    }
                }
            }
        }
    }

    private var summary: String {
        guard model.loaded else { return "Kontrol ediliyor…" }
        let issues = model.checks.filter { $0.level != .good }.count
        return issues == 0 ? "Mac'in iyi durumda" : "\(issues) iyileştirme önerisi"
    }

    private func handle(_ fix: HealthCheck.Fix) {
        switch fix {
        case .module(let m): state.go(m)
        case .restart: confirmRestart = true
        case .reduceMotion: SystemActions.openAccessibilityDisplaySettings()
        case .none: break
        }
    }

    // MARK: - Başlangıç öğeleri

    private var startupCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Başlangıç öğeleri").font(.system(size: 15))
                        Text("Açılışta ve arka planda kendiliğinden çalışan servisler").font(.label(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    PillButton(title: "Giriş öğeleri", icon: "arrow.up.right", style: .raised, compact: true) { SystemActions.openLoginItemsSettings() }
                }
                HStack(spacing: 4) {
                    PillButton(title: "Tümü", style: model.startupFilter == nil ? .dark : .muted, compact: true) { model.startupFilter = nil }
                    ForEach([StartupItem.Scope.user, .allUsers, .system], id: \.self) { s in
                        PillButton(title: s.rawValue, style: model.startupFilter == s ? .dark : .muted, compact: true) { model.startupFilter = s }
                    }
                }
                if model.visibleStartup.isEmpty && model.loaded {
                    Text("Bu kategoride başlangıç öğesi yok.").font(.label(12)).foregroundStyle(Theme.inkMuted).padding(.vertical, 20)
                }
                VStack(spacing: 2) {
                    ForEach(model.visibleStartup) { item in
                        HStack(spacing: 12) {
                            AccentBadge(icon: item.scope == .system ? "gearshape.2" : "person", size: 30, dimmed: !item.enabled)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayName).font(.label(12)).lineLimit(1)
                                Text(item.label).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            RiskBadge(risk: item.insight.risk).fixedSize()
                            InfoButton(insight: item.insight, size: 24)
                            Text(item.scope.rawValue).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1).fixedSize()
                            if model.running.contains(item.id) {
                                ProgressView().controlSize(.small).frame(width: 44)
                            } else {
                                Toggle("", isOn: Binding(get: { item.enabled }, set: { _ in model.toggle(item, using: state) }))
                                    .toggleStyle(.switch).tint(Theme.ink).labelsHidden().controlSize(.small)
                                    .help(item.scope == .system ? "Yönetici şifresi gerekir" : "")
                            }
                            MiniIcon(icon: "folder", help: "Finder'da göster") { SystemActions.revealInFinder(item.plist) }
                        }
                        .padding(.horizontal, 8).frame(height: 48)
                    }
                }
            }
        }
    }

    // MARK: - Bakım

    private var maintenanceCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bakım araçları").font(.system(size: 15))
                ForEach(model.tasks) { task in
                    HStack(spacing: 12) {
                        AccentBadge(icon: model.done.contains(task.id) ? "checkmark" : task.icon, size: 30, dimmed: !model.done.contains(task.id))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(task.title).font(.label(12))
                                if task.needsAdmin { Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(Theme.inkMuted).help("Yönetici şifresi ister") }
                                if task.id == "snapshots" && model.snapshots > 0 { CountBadge(count: model.snapshots) }
                            }
                            Text(task.detail).font(.label(10)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if model.running.contains(task.id) {
                            ProgressView().controlSize(.small).frame(width: 60)
                        } else {
                            PillButton(title: "Çalıştır", style: .raised, compact: true) { model.run(task, using: state) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 12) {
                    AccentBadge(icon: "sparkles", size: 30, dimmed: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Görsel efektleri azalt").font(.label(12))
                        Text("Saydamlığı ve hareketi azaltmak eski Mac'lerde arayüzü hızlandırır.").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    PillButton(title: "Ayarlar", style: .raised, compact: true) { SystemActions.openAccessibilityDisplaySettings() }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Ağır işlemler

    private var heavyCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("İşlemciyi en çok kullananlar").font(.system(size: 15))
                ForEach(model.heavy.prefix(6)) { p in
                    ProcessRow(p: p, total: Int64(ProcessInfo.processInfo.physicalMemory)) { pendingQuit = p }
                }
            }
        }
    }
}

private struct CheckRow: View {
    let check: HealthCheck
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color)
                Image(systemName: check.level == .good ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(check.level == .bad ? .white : Theme.ink)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(.label(12)).lineLimit(1)
                Text(check.detail).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer(minLength: 4)
            if case .none = check.fix {} else if check.level != .good {
                PillButton(title: fixTitle, style: .accent, compact: true, action: action)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceRaised.opacity(check.level == .good ? 0.5 : 1)))
    }

    private var color: Color {
        switch check.level {
        case .good: Theme.success.opacity(0.5)
        case .warn: Theme.accent
        case .bad: Theme.danger
        }
    }

    private var fixTitle: String {
        if case .restart = check.fix { return "Yeniden başlat" }
        return "Düzelt"
    }
}
