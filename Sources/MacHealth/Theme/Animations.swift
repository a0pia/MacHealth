import AppKit
import SwiftUI

// MARK: - Animasyon bütçesi
//
// Sürekli dönen süs animasyonları her karede görünüm ağacını yeniden çizdirir ve boştayken bile
// işlemciyi %75–100 kullanıyordu. Kurallar: en fazla 20 kare/sn, mümkünse tek katmanlı Canvas,
// pencere arka plandayken ya da "Hareketi azalt" açıkken tamamen dur.

private struct LiveAnimationsKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// Pencere öndeyken ve hareket azaltılmamışken true.
    var liveAnimations: Bool {
        get { self[LiveAnimationsKey.self] }
        set { self[LiveAnimationsKey.self] = newValue }
    }
}

/// Süs animasyonları için ortak kare hızı.
enum Motion {
    static let ambient: Double = 1 / 20
    static let active: Double = 1 / 30
}

// MARK: - Sıvı küre (disk doluluğu)

/// İçinde dalgalanan sarı sıvı olan küre. `fraction` doluluk oranı.
struct Wave: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    var frequency: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.height * (1 - level)
        let amp = rect.height * amplitude
        p.move(to: CGPoint(x: 0, y: rect.height))
        for x in stride(from: 0, through: rect.width, by: 4) {
            let rel = Double(x / rect.width)
            let y = baseY + amp * sin(rel * .pi * 2 * frequency + phase)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tarama animasyonu (radar)

struct ScanAnimation: View {
    var icon: String = "sparkle.magnifyingglass"
    var size: CGFloat = 170
    @Environment(\.liveAnimations) private var live

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.active, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // Genişleyen halkalar
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(Theme.ink.opacity(0.25 * (1 - p)), lineWidth: 1)
                        .scaleEffect(0.35 + p * 0.65)
                }
                // Dönen tarama ışını
                Circle()
                    .fill(AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.85)],
                                          center: .center, startAngle: .degrees(0), endAngle: .degrees(90)))
                    .mask(Circle().padding(size * 0.12))
                    .rotationEffect(.degrees(t * 140))
                // Yörüngedeki noktalar
                ForEach(0..<3, id: \.self) { i in
                    let a = t * (1.2 + Double(i) * 0.4) + Double(i) * 2.1
                    let r = size * (0.3 + 0.07 * Double(i))
                    Circle().fill(i == 0 ? Theme.ink : Theme.inkMuted)
                        .frame(width: 6 - CGFloat(i), height: 6 - CGFloat(i))
                        .offset(x: cos(a) * r, y: sin(a) * r)
                }
                // Merkez rozet
                ZStack {
                    Circle().fill(Theme.surfaceRaised)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: size * 0.16))
                        .foregroundStyle(Theme.ink)
                        .scaleEffect(1 + 0.06 * sin(t * 3))
                }
                .frame(width: size * 0.36, height: size * 0.36)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Tarama sırasında dönen ipuçları.
struct ScanTips: View {
    static let tips = [
        "Önbellekleri silmek güvenlidir; uygulamalar ihtiyaç duydukça yeniden oluşturur.",
        "Hiçbir dosya onayın olmadan silinmez. Her şey önce Çöp Kutusu'na gider.",
        "Geçmiş ekranından son temizliği tek tuşla geri alabilirsin.",
        "Diskte %15–20 boş alan bırakmak Mac'in hızlı kalmasına yardım eder.",
        "8 GB RAM'de yavaşlık genelde aynı anda çok sayıda uygulama açıkken başlar.",
        "Tarayıcı önbelleğini silmek şifrelerini ve geçmişini silmez.",
        "Kullanmadığın uygulamaları kaldırmak hem yer açar hem arka plan servislerini azaltır.",
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3.5)) { tl in
            let i = Int(tl.date.timeIntervalSinceReferenceDate / 3.5) % Self.tips.count
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").font(.system(size: 11))
                Text(Self.tips[i]).font(.label(12))
            }
            .foregroundStyle(Theme.inkMuted)
            .id(i)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            .animation(.easeInOut(duration: 0.5), value: i)
        }
        .frame(height: 20)
    }
}

/// "Taranıyor..." yazısında hareketli üç nokta.
struct AnimatedEllipsis: View {
    let text: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { tl in
            let n = Int(tl.date.timeIntervalSinceReferenceDate / 0.4) % 4
            Text(text + String(repeating: ".", count: n) + String(repeating: " ", count: 3 - n))
                .monospacedDigit()
        }
    }
}

// MARK: - Kutlama (konfeti)

struct CelebrationOverlay: View {
    let bytes: Int64
    let dismiss: () -> Void
    @State private var start = Date()
    @State private var appeared = false

    private struct Piece { let x: Double; let delay: Double; let speed: Double; let spin: Double; let size: Double; let color: Color; let shape: Int }

    private let pieces: [Piece] = (0..<70).map { i in
        let colors = [Theme.accent, Theme.ink, Theme.surfaceRaised, Theme.success, Color(hex: 0xF7FCA0)]
        return Piece(x: Double.random(in: 0...1), delay: Double.random(in: 0...0.6), speed: Double.random(in: 0.55...1.1),
                     spin: Double.random(in: -6...6), size: Double.random(in: 6...12), color: colors[i % colors.count], shape: i % 3)
    }

    var body: some View {
        ZStack {
            Theme.frame.opacity(appeared ? 0.35 : 0).ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            TimelineView(.animation(minimumInterval: Motion.active)) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    for p in pieces {
                        let lt = t - p.delay
                        guard lt > 0 else { continue }
                        let y = -20 + lt * p.speed * size.height * 0.7
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(lt * 3 + p.x * 10) * 30
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(lt * p.spin))
                        let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * (p.shape == 1 ? 0.5 : 1))
                        let path = p.shape == 0 ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 2)
                        c.fill(path, with: .color(p.color))
                        if p.color == Theme.surfaceRaised { c.stroke(path, with: .color(Theme.line), lineWidth: 0.5) }
                    }
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 110, height: 110)
                        .scaleEffect(appeared ? 1 : 0.2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .scaleEffect(appeared ? 1 : 0)
                        .rotationEffect(.degrees(appeared ? 0 : -40))
                }
                BytesText(bytes: bytes, size: 44)
                Text("temizlendi · Çöp Kutusu'na taşındı").font(.label(13)).foregroundStyle(Theme.inkMuted)
                PillButton(title: "Harika", style: .dark, action: dismiss).padding(.top, 6)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Theme.surface)
                .shadow(color: .black.opacity(0.15), radius: 30, y: 10))
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - Etkileşim efektleri

/// Üzerine gelince hafifçe yükselen kart efekti.
struct HoverLift: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? 1.012 : 1)
            .shadow(color: .black.opacity(hover ? 0.08 : 0), radius: hover ? 14 : 0, y: hover ? 6 : 0)
            .animation(.spring(duration: 0.3), value: hover)
            .onHover { hover = $0 }
    }
}

/// Basınca küçülen buton stili.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Yüklenirken parlayan şerit efekti.
struct Shimmer: ViewModifier {
    @Environment(\.liveAnimations) private var live
    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation(minimumInterval: Motion.ambient, paused: !live)) { tl in
                let p = (tl.date.timeIntervalSinceReferenceDate / 1.4).truncatingRemainder(dividingBy: 1)
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: -geo.size.width * 0.4 + p * geo.size.width * 1.8)
                }
            }
            .mask(content)
            .allowsHitTesting(false)
        }
    }
}

/// Eskiden sürekli süzülme animasyonuydu; işlemci maliyeti yüzünden artık sabit.
struct Floating: ViewModifier {
    var amount: CGFloat = 5
    func body(content: Content) -> some View { content }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
    func shimmer() -> some View { modifier(Shimmer()) }
    func floating(_ amount: CGFloat = 5) -> some View { modifier(Floating(amount: amount)) }
}
