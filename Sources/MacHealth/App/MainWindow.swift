import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var history: HistoryStore
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let sidebarWidth: CGFloat = 240
    /// Ölçüm için: CLEANER_FORCE_LIVE=1 animasyonları pencere arka plandayken de çalıştırır.
    private static let forceLive = ProcessInfo.processInfo.environment["CLEANER_FORCE_LIVE"] != nil
    private let tabW: CGFloat = 360
    private let tabH: CGFloat = 70

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: Self.sidebarWidth)
                .layoutPriority(1)

            ZStack(alignment: .topLeading) {
                CanvasShape(tabWidth: tabW, tabHeight: tabH, radius: Theme.canvasRadius)
                    .fill(Theme.canvas)
                    .shadow(color: .black.opacity(0.18), radius: 18, x: -4, y: 0)

                header
                    .frame(width: tabW, height: tabH, alignment: .leading)

                StatusPills()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, tabW + 40)
                    .padding(.trailing, 16)
                    .frame(height: tabH - 8)

                content
                    .padding(.top, tabH + 18)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // İçerik ne kadar geniş olursa olsun pencereden taşıp kenar çubuğunu itmesin.
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .padding(.top, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.frame)
        .ignoresSafeArea()
        // Pencere arka plandayken ya da "Hareketi azalt" açıkken süs animasyonları durur.
        .environment(\.liveAnimations, (activeState != .inactive && !reduceMotion) || Self.forceLive)
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(text: toast)
                    .padding(.bottom, 96)
                    .padding(.leading, Self.sidebarWidth)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let bytes = state.celebration {
                CelebrationOverlay(bytes: bytes) { withAnimation(.easeOut(duration: 0.25)) { state.celebration = nil } }
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.easeOut(duration: 0.3)) { state.celebration = nil }
                    }
            }
        }
        .task {
            // Geliştirici: `MacHealth --open <modül>` belirli bir bölümle açar (performans ölçümü için).
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let m = Module(rawValue: args[i + 1]) {
                state.go(m)
            }
        }
        .background {
            // ESC → Ana Sayfa
            Button("") { state.goHome() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
    }

    // MARK: - Başlık sekmesi

    private var header: some View {
        HStack(spacing: 12) {
            if state.module != .smartScan {
                CircleIconButton(icon: "chevron.left", size: 36, help: "Geri (⌘[)") { state.back() }
                    .transition(.scale.combined(with: .opacity))
            } else {
                LogoMark(size: 36)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(state.module.title)
                    .font(.display(26))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(state.module.subtitle)
                    .font(.label(11))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            .id(state.module)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .padding(.trailing, 40)
        .padding(.top, 4)
    }

    // MARK: - İçerik

    private var content: some View {
        ZStack {
            moduleView
                .id(state.module)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 16)).combined(with: .scale(scale: 0.99)),
                    removal: .opacity))
        }
    }

    @ViewBuilder
    private var moduleView: some View {
        switch state.module {
        case .smartScan:
            SmartScanView(junk: state.junk, large: state.largeFiles, uninstaller: state.uninstaller,
                          speed: state.speedUp, memory: state.memory)
        case .junk: JunkView(model: state.junk)
        case .largeFiles: LargeFilesView(model: state.largeFiles)
        case .duplicates: DuplicatesView(model: state.duplicates)
        case .folders: FoldersView(model: state.folders)
        case .diskMap: DiskMapView(model: state.diskMap)
        case .uninstaller: UninstallerView(model: state.uninstaller)
        case .health: HealthView(model: state.health, speed: state.speedUp)
        case .speedUp: SpeedUpView(model: state.speedUp)
        case .memory: MemoryView(model: state.memory)
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Kenar çubuğu

private struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @Namespace private var ns
    @State private var disk = DiskStats.placeholder
    @State private var logoHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo
            HStack(spacing: 10) {
                LogoMark(size: 34, animated: logoHover)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacHealth").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    Text("Mac bakım ve sağlık").font(.label(10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .contentShape(Rectangle())
            .onHover { logoHover = $0 }
            .onTapGesture { state.goHome() }

            AdaptiveScroll {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Module.sections.enumerated()), id: \.offset) { _, section in
                        if let title = section.0 {
                            Text(title.uppercased(with: Locale(identifier: "tr_TR")))
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.38))
                                .padding(.leading, 22)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                        }
                        ForEach(section.1) { m in
                            SidebarItem(module: m, active: state.module == m, badge: state.badge(for: m), ns: ns) { state.go(m) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // Disk mini göstergesi
            Button { state.go(.diskMap) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: "internaldrive").font(.system(size: 11))
                        Text("Macintosh HD").font(.label(11))
                        Spacer()
                        Text("%\(Int(disk.usedFraction * 100))").font(.label(10)).foregroundStyle(.white.opacity(0.5))
                    }
                    CapsuleBar(fraction: disk.usedFraction, fill: Theme.accent, track: .white.opacity(0.12), height: 6)
                    Text("\(Format.bytes(disk.available)) boş · \(Format.bytes(disk.total))")
                        .font(.label(10)).foregroundStyle(.white.opacity(0.55))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 12)

            SidebarItem(module: .settings, active: state.module == .settings, badge: nil, ns: ns) { state.go(.settings) }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
        .task {
            while !Task.isCancelled {
                disk = SystemInfo.disk()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}

private struct SidebarItem: View {
    let module: Module
    let active: Bool
    let badge: String?
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(active ? Theme.accent : .white.opacity(hover ? 0.14 : 0.08))
                    Image(systemName: module.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(active ? Theme.ink : .white.opacity(0.85))
                }
                .frame(width: 30, height: 30)
                Text(module.title)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.ink : .white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(active ? Theme.ink : .white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(active ? Theme.pillMuted : .white.opacity(0.1)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 6).padding(.trailing, 10)
            .frame(height: 42)
            .background {
                if active {
                    Capsule().fill(Theme.surfaceRaised).matchedGeometryEffect(id: "active", in: ns)
                } else if hover {
                    Capsule().fill(.white.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Sağ üst durum hapları

private struct StatusPills: View {
    @EnvironmentObject var state: AppState
    @State private var disk = DiskStats.placeholder
    @State private var mem = MemoryStats.placeholder
    @State private var battery: BatteryInfo?

    var body: some View {
        // Dar pencerede önce etiketler gizlenir, en son sadece ev butonu kalır.
        ViewThatFits(in: .horizontal) {
            pills(compact: false)
            pills(compact: true)
            homeButton
        }
        .task {
            while !Task.isCancelled {
                disk = SystemInfo.disk()
                mem = SystemInfo.memory()
                battery = await Task.detached { BatteryService.read() }.value
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private var homeButton: some View {
        CircleIconButton(icon: "house", size: 38, help: "Ana Sayfa (Esc)") { state.goHome() }
            .opacity(state.module == .smartScan ? 0.4 : 1)
    }

    private func pills(compact: Bool) -> some View {
        HStack(spacing: 6) {
            PillLink(icon: "internaldrive", text: "\(Format.bytes(disk.available)) boş", active: state.module == .diskMap, compact: compact) { state.go(.diskMap) }
            PillLink(icon: "memorychip", text: "RAM %\(Int(mem.usedFraction * 100))", active: state.module == .memory, compact: compact,
                     dot: mem.pressure == .normal ? nil : (mem.pressure == .warning ? Theme.accent : Theme.danger)) { state.go(.memory) }
            if let b = battery {
                PillLink(icon: b.isCharging ? "battery.100.bolt" : "battery.75", text: "Pil %\(b.charge) · sağlık %\(b.healthPercent)",
                         active: state.module == .health, compact: compact, dot: b.healthPercent < 80 ? Theme.danger : nil) { state.go(.health) }
            }
            homeButton
        }
        .fixedSize()
    }
}

/// Sağ üstteki durum hapı; dar pencerede sadece ikon.
private struct PillLink: View {
    let icon: String
    let text: String
    let active: Bool
    var compact = false
    var dot: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                if !compact { Text(text).font(.label(12)).monospacedDigit().lineLimit(1) }
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, compact ? 12 : 14).frame(height: 38)
            .background(Capsule().fill(active ? Theme.surfaceRaised : Color(hex: 0xDEE0D5)))
        }
        .buttonStyle(PressableStyle())
        .help(text)
    }
}

/// Sol üstte başlık sekmesi olan zemin (tema.jpg'deki "Cardiology" sekmesi).
struct CanvasShape: Shape {
    let tabWidth: CGFloat
    let tabHeight: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = radius, c: CGFloat = 38
        let top = tabHeight
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        p.addLine(to: CGPoint(x: tabWidth - c * 0.6, y: 0))
        p.addCurve(to: CGPoint(x: tabWidth + c, y: top),
                   control1: CGPoint(x: tabWidth + c * 0.4, y: 0),
                   control2: CGPoint(x: tabWidth - c * 0.2, y: top))
        p.addLine(to: CGPoint(x: w - r, y: top))
        p.addArc(tangent1End: CGPoint(x: w, y: top), tangent2End: CGPoint(x: w, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        p.addLine(to: CGPoint(x: r, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 8, height: 8)
            Text(text).font(.label(12)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Capsule().fill(Theme.inkDark))
    }
}
