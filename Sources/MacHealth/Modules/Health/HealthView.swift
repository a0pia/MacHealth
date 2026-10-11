import AppKit
import SwiftUI

struct HealthView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: HealthModel
    @ObservedObject var speed: SpeedUpModel
    @State private var showOptimize = false

    var body: some View {
        // Genişliğe göre düzen: geniş pencerede iki sütun, dar pencerede tek sütun.
        GeometryReader { geo in
            let wide = geo.size.width >= 1000
            AdaptiveScroll {
                VStack(spacing: 14) {
                    overview(compact: geo.size.width < 820)
                    if wide {
                        HStack(alignment: .top, spacing: 14) {
                            leftColumn
                            rightColumn.frame(width: min(430, geo.size.width * 0.42))
                        }
                    } else {
                        VStack(spacing: 14) {
                            leftColumn
                            rightColumn
                        }
                    }
                }
                .frame(width: geo.size.width)
                .padding(.bottom, 10)
            }
        }
        .task {
            if !model.loaded { await model.load() }
            if !speed.loaded { await speed.load() }
            model.startLive()
        }
        .onDisappear { model.stopLive() }
        .sheet(isPresented: $showOptimize) {
            OptimizeSheet(runner: OptimizeRunner(firewallOff: model.security?.firewall == false))
                .environmentObject(state)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 14) {
            if let b = model.battery {
                batteryCard(b)
            } else if model.loaded {
                Card { Label("Bu Mac'te pil yok (masaüstü Mac).", systemImage: "powerplug").font(.label(12)) }
            }
            batteryTips
        }
        .frame(maxWidth: .infinity)
    }

    private var rightColumn: some View {
        VStack(spacing: 14) {
            securityCard
            updatesCard
        }
    }

    // MARK: - Genel bakış

    private func overview(compact: Bool) -> some View {
        let score = model.overall(speed: speed)
        let cats = model.categories(speed: speed)
        let ring: CGFloat = compact ? 96 : 130
        let button: CGFloat = compact ? 92 : 118
        return Card(padding: compact ? 16 : 22) {
            HStack(spacing: compact ? 16 : 26) {
                ZStack {
                    RingGauge(fraction: Double(score ?? 0) / 100, lineWidth: 14, color: scoreColor(score ?? 0))
                        .animation(.spring(duration: 1), value: score)
                    VStack(spacing: 0) {
                        Text(score.map { "\($0)" } ?? "–").font(.display(40)).contentTransition(.numericText())
                        Text("Mac sağlığı").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(width: ring, height: ring)

                VStack(alignment: .leading, spacing: 12) {
                    Text(headline(score)).font(.display(compact ? 19 : 24)).lineLimit(2).minimumScaleFactor(0.8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(cats) { c in CategoryTile(category: c, color: scoreColor(c.score)) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { showOptimize = true } label: {
                    ZStack {
                        PulseRing()
                        Circle().fill(Theme.accent).shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 6)
                        VStack(spacing: 4) {
                            Image(systemName: "wand.and.stars").font(.system(size: 24))
                            Text("Optimize et").font(.system(size: compact ? 11 : 13, weight: .medium))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .frame(width: button, height: button)
                }
                .buttonStyle(PressableStyle())
                .help("Tek tıkla güvenli bakım: çöp, bellek, DNS, Launch Services")
            }
        }
    }

    private func headline(_ score: Int?) -> String {
        guard let score else { return "Kontrol ediliyor…" }
        switch score {
        case 90...: return "Mac'in çok sağlıklı"
        case 75..<90: return "Mac'in iyi durumda, birkaç öneri var"
        case 55..<75: return "Mac'in biraz bakıma ihtiyaç duyuyor"
        default: return "Mac'in ilgi bekliyor"
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        s >= 80 ? Theme.accent : (s >= 55 ? Color(hex: 0xF7C948) : Theme.danger)
    }

    // MARK: - Pil

    private func batteryCard(_ b: BatteryInfo) -> some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pil sağlığı").font(.system(size: 16))
                        Text(b.isCharging ? "Şarj oluyor" : (b.pluggedIn ? "Prize takılı" : "Pilde çalışıyor"))
                            .font(.label(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    PillButton(title: "Pil ayarları", icon: "arrow.up.right", style: .raised, compact: true) { SystemActions.open(SettingsLinks.battery) }
                }

                HStack(alignment: .center, spacing: 22) {
                    BatteryGlyph(charge: Double(b.charge) / 100, charging: b.isCharging)
                        .frame(width: 140, height: 62)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], alignment: .leading, spacing: 12) {
                        StatBlock(label: "Maksimum kapasite", value: "\(b.healthPercent)", unit: "%", size: 28)
                        StatBlock(label: "Durum", value: b.condition, size: 18)
                        StatBlock(label: "Şarj", value: "\(b.charge)", unit: "%", size: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Şarj döngüsü").font(.label(11)).foregroundStyle(Theme.inkMuted)
                        Spacer()
                        Text("\(b.cycleCount) / \(b.designCycles)").font(.label(11))
                    }
                    CapsuleBar(fraction: b.cycleFraction, fill: b.cycleFraction > 0.8 ? Theme.danger : Theme.ink, track: Theme.surfaceRaised, height: 8)
                    Text("Apple, pillerin \(b.designCycles) döngüde kapasitesinin %80'ini korumasını hedefler.")
                        .font(.label(10)).foregroundStyle(Theme.inkMuted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], alignment: .leading, spacing: 12) {
                    StatBlock(label: "Sıcaklık", value: String(format: "%.1f", b.temperature), unit: "°C", size: 18)
                    StatBlock(label: "Fabrika kapasitesi", value: "\(b.designCapacity)", unit: "mAh", size: 18)
                    StatBlock(label: "Şu anki kapasite", value: "\(b.fullCapacity)", unit: "mAh", size: 18)
                    if let m = b.minutesRemaining, !b.pluggedIn {
                        StatBlock(label: "Kalan süre", value: "\(m / 60) sa \(m % 60)", unit: "dk", size: 18)
                    }
                    if let w = b.adapterWatts, b.pluggedIn {
                        StatBlock(label: "Adaptör", value: "\(w)", unit: "W", size: 18)
                    }
                }

                if model.history.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        let values = model.history.map { $0.health * 100 }
                        HStack {
                            Text("Pil sağlığı geçmişi").font(.label(11)).foregroundStyle(Theme.inkMuted)
                            Spacer()
                            Text("%\(Int(values.first ?? 0)) → %\(Int(values.last ?? 0))").font(.label(11)).foregroundStyle(Theme.inkMuted)
                        }
                        WaveSparkline(values: values, floor: max(0, (values.min() ?? 0) - 3))
                            .frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Label("Pil sağlığı her gün kaydediliyor; birkaç gün sonra burada değişim grafiği görünecek.", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.label(10)).foregroundStyle(Theme.inkMuted)
                }

                if let i = batteryInsight(b) { InfoBox(insight: i, title: "Pil değerlendirmesi") }
            }
        }
    }

    private func batteryInsight(_ b: BatteryInfo) -> Insight? {
        var notes: [String] = []
        var risk: Insight.Risk = .safe
        if b.healthPercent < 80 {
            notes.append("Kapasite %80'in altında; macOS \"Servis önerilir\" diyebilir. Pil değişimi şarj süresini eski haline getirir.")
            risk = .caution
        } else if b.healthPercent < 85 {
            notes.append("Kapasite %\(b.healthPercent): sınırda ama normal. %80'in altına indiğinde macOS \"Servis önerilir\" der; aşağıdaki ipuçlarıyla bu anı geciktirebilirsin.")
            risk = .low
        } else {
            notes.append("Pil sağlığın iyi durumda.")
        }
        if b.cycleFraction > 0.6 { notes.append("\(b.cycleCount) döngü kullanılmış; ömrünün \(Int(b.cycleFraction * 100))%'i geride kaldı.") }
        if b.temperature > 38 { notes.append("Pil sıcak (\(String(format: "%.0f", b.temperature))°C). Sıcaklık pili en hızlı yıpratan etkendir."); risk = max(risk, .low) }
        return Insight(what: "\(b.fullCapacity) mAh / fabrika \(b.designCapacity) mAh", consequences: notes, risk: risk)
    }

    private var batteryTips: some View {
        let lowPower = model.security?.lowPowerMode ?? false
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AccentBadge(icon: "leaf", size: 30)
                    Text("Pil ömrünü uzatma").font(.system(size: 15))
                }
                tip("bolt.badge.clock", "Optimize Edilmiş Pil Şarjı'nı açık tut", "Mac alışkanlığını öğrenir, gerekene kadar %80'de bekletir.")
                tip("thermometer.medium", "Sıcakta şarj etme", "Yatak/yorgan üstünde veya güneşte şarj pili hızla yıpratır.")
                tip("chart.bar", "%20–80 arasında kullan", "Sürekli %0'a indirmek ya da hep %100'de tutmak kapasiteyi düşürür.")
                tip("gauge.with.dots.needle.33percent", "Parlaklığı ve arka plan uygulamalarını azalt", "Hızlandır › Başlangıç öğeleri'nden gereksiz servisleri kapat.")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Düşük Güç Modu").font(.label(12))
                        Text("Performansı biraz düşürür, pil süresini uzatır.").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if model.running.contains("lowpower") {
                        ProgressView().controlSize(.small)
                    } else {
                        Toggle("", isOn: Binding(get: { lowPower }, set: { model.setLowPower($0, using: state) }))
                            .toggleStyle(.switch).tint(Theme.ink).labelsHidden().controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func tip(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 18).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.label(12))
                Text(detail).font(.label(10)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Güvenlik

    private var securityCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AccentBadge(icon: "lock.shield", size: 30)
                    Text("Güvenlik ve depolama").font(.system(size: 15))
                }
                if let s = model.security {
                    securityRow("Güvenlik duvarı", "İzinsiz gelen bağlantıları engeller.", s.firewall, id: "firewall",
                                fixTitle: "Aç") { model.enableFirewall(using: state) }
                    securityRow("FileVault", "Disk şifreleme; Mac çalınırsa verilerini korur.", s.fileVault, id: "filevault",
                                fixTitle: "Ayarlar") { SystemActions.open(SettingsLinks.security) }
                    securityRow("Gatekeeper", "Doğrulanmamış uygulamaları engeller.", s.gatekeeper, id: "gatekeeper",
                                fixTitle: "Aç") { model.enableGatekeeper(using: state) }
                    securityRow("Sistem Bütünlüğü (SIP)", "Sistem dosyalarını değişikliğe karşı korur.", s.sip, id: "sip",
                                fixTitle: nil) {}
                    securityRow("Otomatik güncelleme", "Güvenlik yamalarını kendiliğinden yükler.", s.autoUpdates, id: "updates",
                                fixTitle: "Ayarlar") { SystemActions.open(SettingsLinks.softwareUpdate) }
                    let smartOK = (s.smart ?? "").lowercased().contains("verified")
                    securityRow("Disk sağlığı (SMART)", smartOK ? "SSD sağlıklı, hata bildirilmedi." : "Durum: \(s.smart ?? "bilinmiyor"). Yedek almayı düşün.",
                                s.smart == nil ? nil : smartOK, id: "smart", fixTitle: nil) {}
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func securityRow(_ title: String, _ detail: String, _ on: Bool?, id: String, fixTitle: String?, fix: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(on == true ? Theme.success.opacity(0.45) : (on == false ? Theme.danger : Theme.pillMuted))
                Image(systemName: on == true ? "checkmark" : (on == false ? "xmark" : "questionmark"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(on == false ? .white : Theme.ink)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.label(12))
                Text(detail).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer()
            if on == false, let fixTitle {
                if model.running.contains(id) {
                    ProgressView().controlSize(.small)
                } else {
                    PillButton(title: fixTitle, style: .accent, compact: true, action: fix)
                }
            } else {
                Text(on == true ? "Açık" : (on == false ? "Kapalı" : "—")).font(.label(11)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.vertical, 3)
    }

    private var updatesCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AccentBadge(icon: "arrow.down.circle", size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sistem güncellemeleri").font(.system(size: 15))
                        Text(SystemInfo.osVersion).font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if model.checkingUpdates {
                        ProgressView().controlSize(.small)
                    } else {
                        PillButton(title: "Denetle", icon: "magnifyingglass", style: .raised, compact: true) { Task { await model.checkUpdates() } }
                    }
                }
                if let u = model.updates {
                    if u.isEmpty {
                        Label("macOS güncel.", systemImage: "checkmark.circle").font(.label(12))
                    } else {
                        ForEach(u, id: \.self) { Text("• \($0)").font(.label(12)) }
                        PillButton(title: "Yazılım Güncelleme'yi aç", icon: "arrow.up.right", style: .accent, compact: true) {
                            SystemActions.open(SettingsLinks.softwareUpdate)
                        }
                    }
                } else {
                    Text("Güncel olmayan macOS, hem güvenlik açığı hem de pil/performans sorunlarına yol açabilir.")
                        .font(.label(10)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }
}

private struct CategoryTile: View {
    let category: HealthModel.Category
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: category.icon).font(.system(size: 11))
                Text(category.title).font(.label(11))
                Spacer(minLength: 0)
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(category.value).font(.display(20)).lineLimit(1).minimumScaleFactor(0.7)
            Text(category.detail).font(.label(9)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            CapsuleBar(fraction: Double(category.score) / 100, fill: color, track: Theme.pillMuted, height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surfaceRaised))
    }
}

/// Pil simgesi: şarj seviyesi kadar dolu, şarj olurken parlayan.
struct BatteryGlyph: View {
    let charge: Double
    let charging: Bool

    var body: some View {
        GeometryReader { geo in
            let capW = geo.size.width * 0.05
            let bodyW = geo.size.width - capW - 3
            HStack(spacing: 3) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: geo.size.height * 0.28, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: geo.size.height * 0.28, style: .continuous).strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2))
                    RoundedRectangle(cornerRadius: geo.size.height * 0.2, style: .continuous)
                        .fill(charge < 0.2 ? Theme.danger : Theme.accent)
                        .frame(width: max(8, (bodyW - 10) * charge))
                        .padding(5)
                        .animation(.spring(duration: 0.8), value: charge)
                    HStack(spacing: 4) {
                        if charging { Image(systemName: "bolt.fill").font(.system(size: 14)) }
                        Text("%\(Int(charge * 100))").font(.display(20))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: bodyW)
                RoundedRectangle(cornerRadius: 3).fill(Theme.ink.opacity(0.7))
                    .frame(width: capW, height: geo.size.height * 0.35)
            }
        }
    }
}

private struct ConditionalShimmer: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.shimmer() } else { content }
    }
}

// MARK: - Optimize sayfası

struct OptimizeSheet: View {
    @EnvironmentObject var state: AppState
    @StateObject var runner: OptimizeRunner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tek tıkla optimize et").font(.display(24))
                    Text(runner.finished ? "Bakım tamamlandı." : "Güvenli bakım adımları. İstemediklerinin işaretini kaldırabilirsin.")
                        .font(.label(12)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                CircleIconButton(icon: "xmark", size: 32) { dismiss() }.disabled(runner.isRunning)
            }

            VStack(spacing: 8) {
                ForEach($runner.steps) { $step in
                    HStack(spacing: 12) {
                        stateIcon(step)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(step.title).font(.label(13))
                                if step.admin { Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(Theme.inkMuted) }
                            }
                            Text(resultText(step) ?? step.detail).font(.label(10)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                        if !runner.isRunning && !runner.finished {
                            Toggle("", isOn: $step.on).toggleStyle(.switch).tint(Theme.ink).labelsHidden().controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                    .opacity(step.on ? 1 : 0.5)
                }
            }

            HStack {
                if runner.needsAdmin && !runner.finished {
                    Label("Kilitli adımlar için yönetici şifren bir kez sorulacak.", systemImage: "lock").font(.label(11)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if runner.finished {
                    PillButton(title: "Kapat", style: .dark) { dismiss() }
                } else {
                    Button { Task { await runner.run(state: state) } } label: {
                        HStack(spacing: 8) {
                            if runner.isRunning { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
                            Text(runner.isRunning ? "Çalışıyor…" : "Başlat").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 22).frame(height: 40)
                        .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(runner.isRunning || !runner.steps.contains { $0.on })
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .interactiveDismissDisabled(runner.isRunning)
    }

    @ViewBuilder
    private func stateIcon(_ step: OptimizeRunner.Step) -> some View {
        switch step.state {
        case .running:
            ZStack { Circle().fill(Theme.surfaceRaised); ProgressView().controlSize(.small) }.frame(width: 32, height: 32)
        case .done:
            AccentBadge(icon: "checkmark", size: 32).transition(.scale)
        case .failed:
            ZStack { Circle().fill(Theme.danger); Image(systemName: "xmark").foregroundStyle(.white).font(.system(size: 12, weight: .bold)) }
                .frame(width: 32, height: 32)
        case .skipped:
            AccentBadge(icon: "minus", size: 32, dimmed: true)
        case .pending:
            AccentBadge(icon: step.icon, size: 32, dimmed: !step.on)
        }
    }

    private func resultText(_ step: OptimizeRunner.Step) -> String? {
        switch step.state {
        case .done(let s): s
        case .failed(let s): s
        case .skipped: "Atlandı"
        case .running: "Çalışıyor…"
        case .pending: nil
        }
    }
}
