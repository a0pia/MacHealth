import AppKit
import SwiftUI

@MainActor
final class MemoryModel: ObservableObject {
    @Published var stats: MemoryStats = SystemInfo.memory()
    @Published var processes: [ProcessInfoRow] = []
    @Published var history: [Double] = []
    @Published var isPurging = false

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task {
            let (s, p) = await Task.detached { (SystemInfo.memory(), SystemInfo.processes()) }.value
            stats = s
            processes = Array(p.sorted { $0.memory > $1.memory }.prefix(25))
            if Demo.isOn && history.isEmpty { history = Demo.memoryHistory }
            history.append(s.usedFraction)
            if history.count > 60 { history.removeFirst(history.count - 60) }
        }
    }

    /// `purge`: disk önbelleğini boşaltır. Yönetici şifresi ister.
    func purge(using state: AppState) async {
        isPurging = true
        let before = SystemInfo.memory()
        let out = await Task.detached { Shell.runAsAdmin("/usr/sbin/purge") }.value
        try? await Task.sleep(for: .seconds(1))
        let after = SystemInfo.memory()
        isPurging = false
        refresh()
        if out.ok {
            let freed = max(0, after.free - before.free)
            state.showToast("Bellek boşaltıldı · \(Format.memory(freed)) serbest kaldı")
            ActivityLog.append("BELLEK purge: \(freed) B serbest")
        } else if !out.stderr.contains("-128") {
            state.showToast("Bellek boşaltılamadı")
        }
    }

    func quit(_ p: ProcessInfoRow, force: Bool, using state: AppState) {
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            _ = force ? app.forceTerminate() : app.terminate()
        } else {
            kill(p.pid, force ? SIGKILL : SIGTERM)
        }
        state.showToast("\(p.name) kapatılıyor…")
        Task { try? await Task.sleep(for: .seconds(1.2)); refresh() }
    }
}

struct MemoryView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: MemoryModel
    @State private var pendingQuit: ProcessInfoRow?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                overview
                breakdown
                ZStack(alignment: .bottom) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not").font(.label(11)).foregroundStyle(Theme.inkMuted)
                            Text("macOS boş belleği önbellek olarak kullanır, bu normaldir. Asıl önemli olan **bellek baskısı** ve **swap**'tir. Baskı sarı/kırmızıysa en çok bellek kullanan uygulamaları kapatmak, \"belleği boşalt\"tan daha kalıcı fayda sağlar.")
                                .font(.label(12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 60)
                        }
                    }
                    BottomActionBar(actionTitle: "Belleği boşalt", actionIcon: "memorychip", busy: model.isPurging) {
                        StatBlock(label: "Önbellek", value: Format.bytesSplit(model.stats.cached, memory: true).0, unit: Format.bytesSplit(model.stats.cached, memory: true).1, size: 18)
                    } action: { Task { await model.purge(using: state) } }
                    .padding(10)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)

            processList.frame(width: 420)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog("\(pendingQuit?.name ?? "") kapatılsın mı?", isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })) {
            if let p = pendingQuit {
                Button("Kapat") { model.quit(p, force: false, using: state) }
                Button("Zorla kapat", role: .destructive) { model.quit(p, force: true, using: state) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş değişiklikler kaybolabilir.")
        }
    }

    private var pressureColor: Color {
        switch model.stats.pressure {
        case .normal: Theme.success
        case .warning: Theme.accent
        case .critical: Theme.danger
        }
    }

    private var overview: some View {
        Card {
            HStack(spacing: 26) {
                ZStack {
                    RingGauge(fraction: model.stats.usedFraction, lineWidth: 14)
                    VStack(spacing: 0) {
                        Text("\(Int(model.stats.usedFraction * 100))").font(.display(34))
                        Text("% kullanımda").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 28) {
                        StatBlock(label: "Kullanılan", value: Format.bytesSplit(model.stats.used, memory: true).0,
                                  unit: "\(Format.bytesSplit(model.stats.used, memory: true).1) / \(Format.memory(model.stats.total))")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bellek baskısı").font(.caption2Muted()).foregroundStyle(Theme.inkMuted)
                            HStack(spacing: 6) {
                                Circle().fill(pressureColor).frame(width: 10, height: 10)
                                Text(model.stats.pressure.title).font(.display(22))
                            }
                        }
                        StatBlock(label: "Swap", value: Format.bytesSplit(model.stats.swapUsed, memory: true).0, unit: Format.bytesSplit(model.stats.swapUsed, memory: true).1)
                    }
                    WaveSparkline(values: model.history.isEmpty ? [0, 0] : model.history)
                        .frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                row("Uygulama belleği", model.stats.app, Theme.ink)
                row("Kablolu (sistem)", model.stats.wired, Theme.inkMuted)
                row("Sıkıştırılmış", model.stats.compressed, Theme.accent)
                row("Önbellek", model.stats.cached, Theme.line)
                row("Boş", model.stats.free, Theme.surfaceRaised)
            }
        }
    }

    private func row(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).overlay(Circle().strokeBorder(Theme.line, lineWidth: color == Theme.surfaceRaised ? 1 : 0)).frame(width: 10, height: 10)
            Text(title).font(.label(12)).frame(width: 130, alignment: .leading)
            CapsuleBar(fraction: Double(bytes) / Double(max(model.stats.total, 1)), fill: color == Theme.surfaceRaised ? Theme.success : color, track: Theme.surfaceRaised, height: 8)
            Text(Format.memory(bytes)).font(.label(11)).foregroundStyle(Theme.inkMuted).frame(width: 70, alignment: .trailing)
        }
    }

    private var processList: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("En çok bellek kullananlar").font(.label(11)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text("CPU").font(.label(10)).foregroundStyle(Theme.inkMuted).frame(width: 44, alignment: .trailing)
                    Text("Bellek").font(.label(10)).foregroundStyle(Theme.inkMuted).frame(width: 70, alignment: .trailing)
                    Color.clear.frame(width: 30)
                }
                .padding(.horizontal, 8)
                AdaptiveScroll {
                    VStack(spacing: 2) {
                        ForEach(model.processes) { p in
                            ProcessRow(p: p, total: model.stats.total) { pendingQuit = p }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct ProcessRow: View {
    let p: ProcessInfoRow
    let total: Int64
    let quit: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = SystemInfo.icon(for: p.pid) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Theme.inkMuted).frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.label(12)).lineLimit(1)
                CapsuleBar(fraction: Double(p.memory) / Double(max(total, 1)) * 4, height: 3)
            }
            Spacer()
            Text(String(format: "%.0f%%", p.cpu)).font(.label(11)).foregroundStyle(Theme.inkMuted).frame(width: 44, alignment: .trailing)
            Text(Format.memory(p.memory)).font(.label(11)).frame(width: 70, alignment: .trailing)
            Button(action: quit) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(hover ? Theme.ink : Theme.pillMuted))
                    .foregroundStyle(hover ? .white : Theme.ink)
            }
            .buttonStyle(.plain).help("Kapat").opacity(p.pid == getpid() ? 0 : 1).disabled(p.pid == getpid())
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(hover ? Theme.surfaceRaised : .clear))
        .onHover { hover = $0 }
    }
}
