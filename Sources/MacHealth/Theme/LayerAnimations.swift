import AppKit
import QuartzCore
import SwiftUI

// Sürekli dönen süs animasyonları Core Animation katmanlarında çalışır: animasyonu macOS'un
// çizim sunucusu oynatır, uygulama her karede yeniden çizim yapmaz (boşta ~%0 işlemci).

private extension Color {
    var cg: CGColor { NSColor(self).cgColor }
}

// MARK: - Sıvı küre (disk doluluğu)

/// İçinde dalgalanan sarı sıvı ve yükselen kabarcıklar olan küre. `fraction` doluluk oranı.
struct LiquidGauge: NSViewRepresentable {
    let fraction: Double
    @Environment(\.liveAnimations) private var live

    func makeNSView(context: Context) -> LiquidGaugeView { LiquidGaugeView() }

    func updateNSView(_ view: LiquidGaugeView, context: Context) {
        view.update(fraction: fraction, live: live)
    }
}

final class LiquidGaugeView: NSView {
    private let container = CALayer()
    private let circleMask = CAShapeLayer()
    private let back = CAShapeLayer()
    private let waves = [CAShapeLayer(), CAShapeLayer()]
    private let bubbles = CAEmitterLayer()
    private var fraction: Double = 0
    private var live = true
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Katmanı kendimiz oluşturuyoruz (layer-hosting); `wantsLayer` tek başına katmanı hemen yaratmaz.
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(container)
        container.addSublayer(back)
        waves.forEach { container.addSublayer($0) }
        container.addSublayer(bubbles)
        container.mask = circleMask
        back.fillColor = Theme.surfaceRaised.cg
        waves[0].fillColor = Theme.accent.opacity(0.45).cg
        waves[1].fillColor = Theme.accent.cg
        configureBubbles()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(fraction newValue: Double, live newLive: Bool) {
        let changed = abs(newValue - fraction) > 0.001
        fraction = newValue
        if newLive != live { live = newLive; builtSize = .zero }
        if changed || builtSize != bounds.size { rebuild(animated: changed && builtSize == bounds.size) }
    }

    override func layout() {
        super.layout()
        if builtSize != bounds.size { rebuild(animated: false) }
    }

    private func rebuild(animated: Bool) {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(1.0)
        container.frame = b
        circleMask.path = CGPath(ellipseIn: b, transform: nil)
        back.path = CGPath(rect: b, transform: nil)

        // (genlik, dalga sayısı, süre, faz)
        let specs: [(CGFloat, CGFloat, CFTimeInterval, CGFloat)] = [(0.035, 1.4, 3.6, 0), (0.03, 1.1, 2.6, 1.7)]
        for (layer, spec) in zip(waves, specs) {
            let wavelength = b.width / spec.1
            let width = b.width + wavelength
            layer.bounds = CGRect(x: 0, y: 0, width: width, height: b.height)
            layer.anchorPoint = CGPoint(x: 0, y: 0)
            layer.position = .zero
            layer.path = wavePath(width: width, height: b.height, level: CGFloat(fraction),
                                  amplitude: b.height * spec.0, wavelength: wavelength, phase: spec.3)
            if layer.animation(forKey: "flow") == nil || !animated {
                layer.removeAnimation(forKey: "flow")
                if live {
                    // Bir dalga boyu kadar kaydır → kesintisiz döngü
                    let a = CABasicAnimation(keyPath: "position.x")
                    a.fromValue = 0
                    a.toValue = -wavelength
                    a.duration = spec.2
                    a.repeatCount = .infinity
                    a.timingFunction = CAMediaTimingFunction(name: .linear)
                    layer.add(a, forKey: "flow")
                }
            }
        }

        bubbles.frame = b
        bubbles.emitterPosition = CGPoint(x: b.midX, y: 4)
        bubbles.emitterSize = CGSize(width: b.width * 0.55, height: 1)
        bubbles.birthRate = live ? 1 : 0
        if let cell = bubbles.emitterCells?.first {
            cell.lifetime = Float(max(0.6, Double(b.height) * fraction / 18))
        }
        CATransaction.commit()
        builtSize = b.size
    }

    private func wavePath(width: CGFloat, height: CGFloat, level: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let base = height * level   // katman koordinatları alttan yukarı
        p.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        while x <= width {
            p.addLine(to: CGPoint(x: x, y: base + amplitude * sin(x / wavelength * .pi * 2 + phase)))
            x += 3
        }
        p.addLine(to: CGPoint(x: width, y: 0))
        p.closeSubpath()
        return p
    }

    private func configureBubbles() {
        let size = 12
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            return true
        }
        let cell = CAEmitterCell()
        cell.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.birthRate = 1.6
        cell.lifetime = 4
        cell.velocity = 18
        cell.velocityRange = 6
        cell.emissionLongitude = .pi / 2
        cell.xAcceleration = 0
        cell.scale = 0.45
        cell.scaleRange = 0.2
        cell.alphaSpeed = -0.22
        cell.color = NSColor.white.withAlphaComponent(0.8).cgColor
        bubbles.emitterShape = .line
        bubbles.emitterCells = [cell]
    }
}

// MARK: - Nabız halkası

/// Nabız gibi dışa açılıp kaybolan iki halka (dikkat çekmek için).
struct PulseRing: View {
    var color: Color = Theme.accent
    private static let bleed: CGFloat = 40
    @Environment(\.liveAnimations) private var live

    var body: some View {
        PulseRingLayer(color: color, live: live, bleed: Self.bleed)
            .padding(-Self.bleed)       // halkalar çerçevenin dışına taşabilsin
            .allowsHitTesting(false)
    }
}

private struct PulseRingLayer: NSViewRepresentable {
    let color: Color
    let live: Bool
    let bleed: CGFloat

    func makeNSView(context: Context) -> PulseRingView { PulseRingView() }
    func updateNSView(_ view: PulseRingView, context: Context) { view.update(color: color, live: live, bleed: bleed) }
}

final class PulseRingView: NSView {
    private let rings = [CAShapeLayer(), CAShapeLayer()]
    private var color: CGColor = NSColor.yellow.cgColor
    private var live = true
    private var bleed: CGFloat = 0
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        rings.forEach {
            $0.fillColor = nil
            $0.lineWidth = 2
            layer?.addSublayer($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: Color, live: Bool, bleed: CGFloat) {
        let cg = color.cg
        let needs = live != self.live || bleed != self.bleed || cg != self.color
        guard needs else { return }   // Her SwiftUI güncellemesinde yeniden yerleşim isteme: sonsuz döngüye giriyordu.
        self.color = cg
        self.live = live
        self.bleed = bleed
        builtSize = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.size != builtSize, bounds.width > bleed * 2 else { return }
        builtSize = bounds.size
        let inner = bounds.insetBy(dx: bleed, dy: bleed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, ring) in rings.enumerated() {
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: inner, transform: nil)
            ring.strokeColor = color
            ring.removeAllAnimations()
            guard live else { ring.opacity = 0; continue }
            ring.opacity = 0.9

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 1.45
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.8
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.9
            group.fillMode = .backwards
            ring.add(group, forKey: "pulse")
        }
        CATransaction.commit()
    }
}
