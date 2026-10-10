import AppKit
import SwiftUI

/// MacHealth logosu: koyu zemin üzerinde katlanmış kâğıt gibi iki yüzlü "M"; içinden geçen sarı nabız
/// çizgisi H'nin orta çizgisini oluşturur (M + H = MacHealth).
/// Uygulama ikonu ve logo PNG'si de bu görünümden üretilir (`--render-icon`, `--render-logo`).
struct LogoMark: View {
    var size: CGFloat = 64
    /// Nabız çizgisi üzerinde bir ışık dolaşır, arka plan ışığı nefes alır.
    var animated = false
    /// İkon için: kenarlarda macOS ikon boşluğu bırakır.
    var iconPadding = false
    @Environment(\.liveAnimations) private var live

    var body: some View {
        let moving = animated && live
        TimelineView(.animation(minimumInterval: Motion.active, paused: !moving)) { tl in
            let t = moving ? tl.date.timeIntervalSinceReferenceDate : 0
            canvas(t: t, moving: moving)
        }
        .frame(width: size, height: size)
    }

    private func canvas(t: Double, moving: Bool) -> some View {
        let s = iconPadding ? size * 0.82 : size
        let r = s * 0.235
        let lw = s * 0.042
        let mark = CGSize(width: s * 0.56, height: s * 0.52)
        let beat = moving ? (t * 0.55).truncatingRemainder(dividingBy: 1) : 0
        return ZStack {
            // Zemin
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x62635F), Color(hex: 0x34352F)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom), lineWidth: max(1, s * 0.012))
            // Arka plandaki yumuşak sarı ışık
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.45))
                .frame(width: s * 0.9, height: s * 0.9)
                .opacity(moving ? 0.75 + 0.25 * sin(t * 2.4) : 1)

            ZStack {
                // M: iki yüzlü (sağ yarı hafif gölgede) — katlanmış kâğıt / küp etkisi
                MonogramShape(lineWidth: lw)
                    .fill(LinearGradient(colors: [Color(hex: 0xF4F1E6), Color(hex: 0xCFCBBE)], startPoint: .top, endPoint: .bottom))
                MonogramShape(lineWidth: lw)
                    .fill(Color.black.opacity(0.10))
                    .mask(HStack(spacing: 0) { Color.clear; Color.black })
                // Nabız (H'nin orta çizgisi)
                PulseLine()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                if moving {
                    PulseLine()
                        .trim(from: max(0, beat - 0.18), to: beat)
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lw * 0.55, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: mark.width, height: mark.height)
            .shadow(color: .black.opacity(0.3), radius: s * 0.02, y: s * 0.015)
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .frame(width: size, height: size)
    }
}

/// Menü çubuğu için tek renkli (şablon) M + nabız simgesi.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let view = MonogramShape(lineWidth: 1.4, cutPulse: true)
            .fill(Color.black, style: FillStyle(eoFill: false))
            .frame(width: 16, height: 15)
            .frame(width: 18, height: 18)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = r.nsImage ?? NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)!
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()
}

/// Pahlı köşeli, üstü çentikli "M" silüeti; nabız çizgisinin geçtiği yer oyuk bırakılır.
private struct MonogramShape: Shape {
    var lineWidth: CGFloat
    /// true: nabız çizgisini de oyar (tek renkli kullanım için çizginin kendisi boşlukta kalır).
    var cutPulse = false

    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var m = Path()
        m.addLines([pt(0, 0.16), pt(0.14, 0.02), pt(0.30, 0.02), pt(0.5, 0.22), pt(0.70, 0.02), pt(0.86, 0.02), pt(1, 0.16),
                    pt(1, 0.98), pt(0.78, 0.98), pt(0.78, 0.36), pt(0.5, 0.60), pt(0.22, 0.36), pt(0.22, 0.98), pt(0, 0.98)])
        m.closeSubpath()
        // Köşeleri hafifçe yuvarla
        m = m.union(m.strokedPath(StrokeStyle(lineWidth: lineWidth * 0.5, lineJoin: .round)))
        // Nabız çizgisinin çevresinde oluk
        let pulse = PulseLine().path(in: r)
        m = m.subtracting(pulse.strokedPath(StrokeStyle(lineWidth: lineWidth * 2.2, lineCap: .round, lineJoin: .round)))
        if cutPulse {
            m = m.union(pulse.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)))
        }
        return m
    }
}

/// İki ayağı birleştiren nabız (EKG) çizgisi.
private struct PulseLine: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.addLines([pt(0.13, 0.80), pt(0.35, 0.80), pt(0.42, 0.70), pt(0.52, 0.93), pt(0.60, 0.80), pt(0.87, 0.80)])
        return p
    }
}

/// Uygulama ikonu ve logo PNG'si üretir:
/// `MacHealth --render-icon <klasör.iconset>` · `MacHealth --render-logo <dosya.png> [boyut]`
@MainActor
enum IconRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-logo"), i + 1 < args.count {
            let px = i + 2 < args.count ? Int(args[i + 2]) ?? 1024 : 1024
            write(LogoMark(size: CGFloat(px), iconPadding: true), to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        guard let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                write(LogoMark(size: CGFloat(px), iconPadding: true), to: dir.appendingPathComponent(name))
            }
        }
        return true
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let cg = r.cgImage else { return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
    }
}
