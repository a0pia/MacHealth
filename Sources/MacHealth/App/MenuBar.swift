import AppKit
import SwiftUI
@preconcurrency import UserNotifications

/// Menü çubuğu paneli: disk ve RAM özeti, hızlı eylemler.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var disk = DiskStats.placeholder
    @State private var mem = MemoryStats.placeholder
    @State private var purging = false
    @State private var battery: BatteryInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LogoMark(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacHealth").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(SystemInfo.osVersion).font(.label(10)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                gauge(title: "Disk", fraction: disk.usedFraction, detail: "\(Format.bytes(disk.available)) boş")
                gauge(title: "Bellek", fraction: mem.usedFraction, detail: mem.pressure.title)
                if let b = battery {
                    gauge(title: "Pil", fraction: Double(b.charge) / 100, detail: "Sağlık %\(b.healthPercent)", invert: true)
                }
            }

            VStack(spacing: 6) {
                action("Akıllı Tarama", icon: "sparkle.magnifyingglass") { open(.smartScan) }
                action("Mac Sağlığı ve optimize", icon: "heart.text.square") { open(.health) }
                action("Sistem Çöpü", icon: "trash") { open(.junk) }
                action(purging ? "Boşaltılıyor…" : "Belleği boşalt", icon: "memorychip") {
                    purging = true
                    Task {
                        await state.memory.purge(using: state)
                        mem = SystemInfo.memory()
                        purging = false
                    }
                }
                action("Uygulamalar", icon: "square.grid.2x2") { open(.uninstaller) }
            }

            HStack {
                Button("Ayarlar") { open(.settings) }.buttonStyle(.plain).font(.label(11)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.label(11)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .environment(\.colorScheme, .light)
        .task {
            while !Task.isCancelled {
                disk = SystemInfo.disk()
                mem = SystemInfo.memory()
                battery = await Task.detached { BatteryService.read() }.value
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func open(_ m: Module) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        state.go(m)
    }

    private func gauge(title: String, fraction: Double, detail: String, invert: Bool = false) -> some View {
        let warn = invert ? fraction < 0.2 : fraction > 0.9
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.label(11)).foregroundStyle(Theme.inkMuted)
            Text("%\(Int(fraction * 100))").font(.display(20)).foregroundStyle(Theme.ink)
            CapsuleBar(fraction: fraction, fill: warn ? Theme.danger : Theme.accent, track: Theme.surfaceRaised, height: 6)
            Text(detail).font(.label(9)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func action(_ title: String, icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                AccentBadge(icon: icon, size: 26)
                Text(title).font(.label(12)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 8).frame(height: 38)
            .background(Capsule().fill(Theme.surfaceRaised))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Boş alan eşiğin altına düşünce bildirim gönderir (uygulama veya menü çubuğu açıkken).
@MainActor
final class DiskWatcher {
    static let shared = DiskWatcher()
    private var timer: Timer?
    private var lastNotified: Date?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in DiskWatcher.shared.check() }
        }
        check()
    }

    func check() {
        guard UserDefaults.standard.object(forKey: Settings.lowDiskAlertKey) as? Bool ?? true else { return }
        let threshold = Double(UserDefaults.standard.object(forKey: Settings.lowDiskPercentKey) as? Int ?? 10) / 100
        let d = SystemInfo.disk()
        guard d.freeFraction < threshold else { return }
        if let last = lastNotified, Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastNotified = Date()
        let body = "Sadece \(Format.bytes(d.available)) boş kaldı. MacHealth ile yer açabilirsin."
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Disk alanı azaldı"
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowdisk", content: content, trigger: nil))
        }
    }
}
