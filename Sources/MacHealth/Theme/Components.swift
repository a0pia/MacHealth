import SwiftUI

// MARK: - Haplar (pill)

enum PillStyle { case raised, muted, dark, accent }

struct PillButton: View {
    let title: String
    var icon: String? = nil
    var style: PillStyle = .muted
    var compact = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: compact ? 11 : 12, weight: .regular)) }
                Text(title).font(.label(compact ? 11 : 12)).lineLimit(1)
            }
            .padding(.horizontal, compact ? 14 : 18)
            .frame(height: compact ? 30 : 38)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(Color.black.opacity(style == .muted && hover ? 0.08 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }

    private var background: Color {
        switch style {
        case .raised: Theme.surfaceRaised
        case .muted: hover ? Theme.surface : Theme.pillMuted
        case .dark: Theme.inkDark
        case .accent: Theme.accent
        }
    }

    private var foreground: Color {
        switch style {
        case .dark: .white
        default: Theme.ink
        }
    }
}

struct CircleIconButton: View {
    let icon: String
    var dark = false
    var size: CGFloat = 40
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .regular))
                .foregroundStyle(dark ? .white : Theme.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(dark ? Theme.ink : Theme.surfaceRaised))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help ?? "")
    }
}

/// Görseldeki sarı daire rozet.
struct AccentBadge: View {
    let icon: String
    var size: CGFloat = 40
    var dimmed = false

    var body: some View {
        ZStack {
            Circle().fill(dimmed ? Theme.pillMuted : Theme.accent)
            Image(systemName: icon)
                .font(.system(size: size * 0.38))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
    }
}

struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Theme.accent))
    }
}

// MARK: - Kart

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var fill: Color = Theme.surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(fill))
    }
}

// MARK: - Sayı blokları

/// "Kullanılan  412 / 512 GB" gibi küçük etiket + büyük ince sayı.
struct StatBlock: View {
    let label: String
    let value: String
    var unit: String = ""
    var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2Muted()).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.display(size)).foregroundStyle(Theme.ink)
                if !unit.isEmpty {
                    Text(unit).font(.label(size * 0.45)).foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

struct BytesText: View {
    let bytes: Int64
    var size: CGFloat = 28
    var body: some View {
        let (v, u) = Format.bytesSplit(bytes)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(v).font(.display(size))
            Text(u).font(.label(size * 0.42))
        }
        .foregroundStyle(Theme.ink)
        .contentTransition(.numericText())
    }
}

// MARK: - Çubuklar

struct CapsuleBar: View {
    let fraction: Double
    var fill: Color = Theme.accent
    var track: Color = Theme.pillMuted
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Görseldeki hatchli + sarı dolgulu dalga grafiği benzeri basit alan grafiği.
struct WaveSparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(
                    x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(v / maxV) * 0.85)
                )
            }
            ZStack {
                smooth(pts, close: true, height: geo.size.height)
                    .fill(Theme.accent)
                smooth(pts, close: false, height: geo.size.height)
                    .stroke(Theme.ink.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private func smooth(_ pts: [CGPoint], close: Bool, height: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            if close { p.move(to: CGPoint(x: first.x, y: height)); p.addLine(to: first) } else { p.move(to: first) }
            for i in 1..<max(pts.count, 1) where i < pts.count {
                let a = pts[i - 1], b = pts[i]
                let mid = (a.x + b.x) / 2
                p.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            }
            if close, let last = pts.last { p.addLine(to: CGPoint(x: last.x, y: height)); p.closeSubpath() }
        }
    }
}

struct RingGauge: View {
    let fraction: Double
    var lineWidth: CGFloat = 12
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(Theme.pillMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Alt aksiyon barı (görseldeki beyaz yüzen zaman çizelgesi)

struct BottomActionBar<Leading: View>: View {
    let actionTitle: String
    var actionIcon: String = "sparkles"
    var enabled = true
    var busy = false
    @ViewBuilder var leading: Leading
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            leading
            Spacer(minLength: 12)
            Button(action: action) {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: actionIcon).font(.system(size: 12))
                    }
                    Text(actionTitle).font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(enabled ? Theme.ink : Theme.inkMuted)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background(Capsule().fill(enabled ? Theme.accent : Theme.pillMuted))
            }
            .buttonStyle(PressableStyle())
            .disabled(!enabled || busy)
        }
        .padding(.leading, 22)
        .padding(.trailing, 6)
        .frame(height: 54)
        .background(Capsule().fill(Theme.surfaceRaised).shadow(color: .black.opacity(0.06), radius: 12, y: 4))
    }
}

// MARK: - Yardımcı görünümler

struct ModuleHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.display(26)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.label(12)).foregroundStyle(Theme.inkMuted)
        }
    }
}

struct SelectBox: View {
    let state: SelectionState
    var body: some View {
        ZStack {
            Circle().fill(state == .none ? Theme.surfaceRaised : Theme.ink)
            Circle().strokeBorder(Theme.line, lineWidth: state == .none ? 1 : 0)
            switch state {
            case .all: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
            case .some: Image(systemName: "minus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
            case .none: EmptyView()
            }
        }
        .frame(width: 20, height: 20)
    }
}

enum SelectionState { case none, some, all }

struct ScanningPlaceholder: View {
    let text: String
    var icon: String = "sparkle.magnifyingglass"

    var body: some View {
        VStack(spacing: 22) {
            ScanAnimation(icon: icon, size: 180)
            AnimatedEllipsis(text: text).font(.display(20)).foregroundStyle(Theme.ink)
            ScanTips()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                PulseRing().frame(width: 84, height: 84)
                AccentBadge(icon: icon, size: 84)
            }
            .floating(4)
            .padding(.bottom, 8)
            Text(title).font(.display(24)).foregroundStyle(Theme.ink)
            Text(message).font(.label(12)).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12))
                        Text(actionTitle).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Tam Disk Erişimi uyarısı (izin verildiyse görünmez).
struct FullDiskAccessBanner: View {
    var title = "Bazı klasörlere erişilemedi"
    var message = "Daha kapsamlı tarama için MacHealth'e bir kez Tam Disk Erişimi ver."
    @ObservedObject private var perms = PermissionCenter.shared

    var body: some View {
        if !perms.fullDiskAccess {
            HStack(spacing: 12) {
                AccentBadge(icon: "lock.open", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(message).font(.label(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PillButton(title: "İzin ver", icon: "lock.open", style: .dark, compact: true) { Permissions.requestFullDiskAccess() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        }
    }
}

/// Ayarlar'daki izin kartı: durum + adım adım tek seferlik kurulum.
struct PermissionsPanel: View {
    @ObservedObject private var perms = PermissionCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: perms.fullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(perms.fullDiskAccess ? Theme.success : Theme.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tam Disk Erişimi").font(.label(12))
                    Text(perms.fullDiskAccess
                         ? "Verildi. macOS artık her uygulama için ayrı ayrı izin sormaz."
                         : "Verilmedi. Uygulamaların veri klasörleri (Containers) atlanıyor; her biri için macOS ayrı izin sorardı.")
                        .font(.label(10)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !perms.fullDiskAccess {
                    PillButton(title: "İzin ver", icon: "lock.open", style: .dark, compact: true) { Permissions.requestFullDiskAccess() }
                }
            }
            if !perms.fullDiskAccess {
                VStack(alignment: .leading, spacing: 4) {
                    step(1, "**İzin ver**'e bas: Sistem Ayarları › Tam Disk Erişimi açılır, Finder'da MacHealth seçili gelir.")
                    step(2, "Listede MacHealth varsa anahtarını aç; yoksa Finder'daki MacHealth'i listeye sürükle.")
                    step(3, "Buraya dön; durum kendiliğinden güncellenir. Gerekirse **Yeniden başlat**.")
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                HStack(spacing: 6) {
                    PillButton(title: "Durumu yenile", icon: "arrow.clockwise", style: .raised, compact: true) { perms.refresh() }
                    PillButton(title: "Yeniden başlat", icon: "arrow.triangle.2.circlepath", style: .raised, compact: true) { Permissions.relaunch() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accent))
            Text(.init(text)).font(.label(11)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Kaydırma

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Snapshot (ImageRenderer) modunda ScrollView çizilemediği için içerik düz gösterilir.
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct AdaptiveScroll<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshot
    @ViewBuilder var content: Content

    var body: some View {
        if snapshot {
            VStack(spacing: 0) { content }.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView { content }.scrollIndicators(.never)
        }
    }
}
