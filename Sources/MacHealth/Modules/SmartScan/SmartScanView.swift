import SwiftUI

struct SmartScanView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var junk: JunkModel
    @ObservedObject var large: LargeFilesModel
    @ObservedObject var uninstaller: UninstallerModel
    @ObservedObject var speed: SpeedUpModel
    @ObservedObject var memory: MemoryModel

    @State private var disk = DiskStats.placeholder
    @State private var scanning = false
    @State private var cleaning = false
    @State private var showSummary = false

    private var hasResults: Bool { junk.hasScanned || large.hasScanned || uninstaller.orphansScanned }

    /// Akıllı temizlikte silinecekler: sistem çöpü + kurulum dosyaları (varsayılan seçimler).
    private var cleanable: [CleanItem] { junk.selectedItems + large.selectedItems }
    private var cleanableSize: Int64 { cleanable.reduce(0) { $0 + $1.size } }

    var body: some View {
        AdaptiveScroll {
            VStack(alignment: .leading, spacing: 16) {
                hero
                timeline.padding(.top, 4)
                cards
                quickActions
                SpaceInsightsCard(model: state.insights)
                bottomBar
            }
            .padding(.bottom, 10)
        }
        .onAppear {
            disk = SystemInfo.disk()
            memory.refresh()
            Task { if !uninstaller.isLoading && uninstaller.apps.isEmpty { await uninstaller.load() } }
            Task { if !state.health.loaded { await state.health.load() } }
        }
        .sheet(isPresented: $showSummary) {
            CleanSummarySheet(title: "Akıllı temizlik", lines: CleanSummarySheet.Line.from(junk) + CleanSummarySheet.Line.from(large)) {
                Task { await clean() }
            }
        }
    }

    // MARK: - Kahraman alanı

    private var hero: some View {
        Card(padding: 24) {
            HStack(spacing: 30) {
                ZStack {
                    LiquidGauge(fraction: disk.usedFraction)
                    VStack(spacing: 0) {
                        Text("%\(Int(disk.usedFraction * 100))").font(.display(36)).foregroundStyle(Theme.ink)
                        Text("dolu").font(.label(11)).foregroundStyle(Theme.ink.opacity(0.7))
                    }
                }
                .frame(width: 170, height: 170)

                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        if scanning {
                            VStack(alignment: .leading, spacing: 8) {
                                AnimatedEllipsis(text: "Mac'in taranıyor").font(.display(30))
                                ScanTips()
                            }
                        } else if hasResults {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    BytesText(bytes: cleanableSize, size: 40)
                                    Text("güvenle temizlenebilir").font(.display(20)).foregroundStyle(Theme.ink)
                                }
                                Text(resultSummary).font(.label(12)).foregroundStyle(Theme.inkMuted)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(greeting).font(.display(30)).foregroundStyle(Theme.ink)
                                Text("Sistem çöpü, büyük dosyalar, uygulama artıkları ve Mac sağlığı tek seferde kontrol edilir. Hiçbir şey onayın olmadan silinmez.")
                                    .font(.label(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))

                    HStack(spacing: 34) {
                        StatBlock(label: "Kullanılan", value: Format.bytesSplit(disk.used).0, unit: "/ \(Format.bytes(disk.total))", size: 22)
                        StatBlock(label: "Boş", value: Format.bytesSplit(disk.available).0, unit: Format.bytesSplit(disk.available).1, size: 22)
                        StatBlock(label: "Bellek", value: "\(Int(memory.stats.usedFraction * 100))", unit: "%", size: 22)
                        StatBlock(label: "Mac sağlığı", value: speed.loaded ? "\(speed.score)" : "–", unit: "/ 100", size: 22)
                    }
                }
                Spacer(minLength: 10)
                bigButton
            }
        }
        .animation(.spring(duration: 0.4), value: scanning)
        .animation(.spring(duration: 0.4), value: hasResults)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let g = h < 6 ? "İyi geceler" : h < 12 ? "Günaydın" : h < 18 ? "İyi günler" : "İyi akşamlar"
        return "\(g), Mac'ini tarayalım mı?"
    }

    private var resultSummary: String {
        var parts: [String] = []
        if junk.hasScanned { parts.append("Sistem çöpü \(Format.bytes(junk.result.totalSize))") }
        if large.hasScanned { parts.append("büyük dosyalar \(Format.bytes(large.result.totalSize))") }
        if uninstaller.orphansScanned { parts.append("artıklar \(Format.bytes(uninstaller.orphans.reduce(0) { $0 + $1.size }))") }
        return parts.joined(separator: " · ") + " bulundu"
    }

    /// Ortadaki büyük yuvarlak buton.
    private var bigButton: some View {
        let canClean = hasResults && !cleanable.isEmpty
        return Button {
            if canClean { showSummary = true } else { Task { await scanAll() } }
        } label: {
            ZStack {
                if !scanning && !cleaning { PulseRing(color: canClean ? Theme.accent : Theme.ink.opacity(0.4)) }
                Circle().fill(canClean ? Theme.accent : Theme.ink)
                    .shadow(color: (canClean ? Theme.accent : Theme.ink).opacity(0.35), radius: 16, y: 6)
                if scanning || cleaning {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: canClean ? "sparkles" : "magnifyingglass").font(.system(size: 26))
                        Text(canClean ? "Temizle" : (hasResults ? "Yeniden tara" : "Tara")).font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(canClean ? Theme.ink : .white)
                }
            }
            .frame(width: 128, height: 128)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(scanning || cleaning)
        .keyboardShortcut(.return, modifiers: .command)
        .help(canClean ? "Seçilenleri temizle (⌘↩)" : "Akıllı tarama başlat (⌘↩)")
    }

    // MARK: - Zaman çizelgesi (sarı rozetler + renkli çizgi)

    private var steps: [(Module, String, Bool)] {
        [
            (.junk, "trash", junk.hasScanned),
            (.largeFiles, "doc.badge.ellipsis", large.hasScanned),
            (.uninstaller, "questionmark.folder", uninstaller.orphansScanned),
            (.speedUp, "bolt", speed.loaded),
        ]
    }

    private var timeline: some View {
        GeometryReader { geo in
            let n = CGFloat(steps.count)
            let spacing: CGFloat = 14
            let cardW = (geo.size.width - spacing * (n - 1)) / n
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line).frame(height: 1)
                LinearGradient(colors: [Theme.danger.opacity(0.7), Theme.accent, Theme.success], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * progress, height: 2)
                    .animation(.spring(duration: 0.8), value: progress)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    ZStack {
                        if scanning && !step.2 { PulseRing().frame(width: 34, height: 34) }
                        AccentBadge(icon: step.2 ? "checkmark" : step.1, size: 34, dimmed: !step.2 && !scanning)
                    }
                    .offset(x: CGFloat(i) * (cardW + spacing) + 18)
                    .animation(.spring(duration: 0.4), value: step.2)
                }
            }
            .frame(height: 34)
        }
        .frame(height: 34)
    }

    private var progress: CGFloat {
        CGFloat(steps.filter(\.2).count) / CGFloat(steps.count)
    }

    // MARK: - Modül kartları

    private var cards: some View {
        HStack(alignment: .top, spacing: 14) {
            ModuleCard(title: "Sistem Çöpü", subtitle: junk.hasScanned ? "\(junk.result.allItems.count) öğe" : "Önbellek, log, geçici",
                       bytes: junk.hasScanned ? junk.result.totalSize : nil,
                       spark: junk.result.groups.map { Double($0.totalSize) },
                       busy: junk.isScanning) { state.go(.junk) }
            ModuleCard(title: "Büyük Dosyalar", subtitle: large.hasScanned ? "\(large.result.allItems.count) dosya" : "Büyük, eski, indirilenler",
                       bytes: large.hasScanned ? large.result.totalSize : nil,
                       spark: large.result.groups.map { Double($0.totalSize) },
                       busy: large.isScanning) { state.go(.largeFiles) }
            ModuleCard(title: "Uygulama Artıkları", subtitle: uninstaller.orphansScanned ? "\(uninstaller.orphans.count) sahipsiz öğe" : "Silinmiş uygulamalardan kalan",
                       bytes: uninstaller.orphansScanned ? uninstaller.orphans.reduce(0) { $0 + $1.size } : nil,
                       spark: uninstaller.orphans.prefix(12).map { Double($0.size) },
                       busy: uninstaller.loadingOrphans) {
                uninstaller.tab = .orphans
                state.go(.uninstaller)
            }
            SpeedCard(model: speed) { state.go(.speedUp) }
        }
.frame(height: 210)
    }

    // MARK: - Hızlı işlemler

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickAction(icon: "moon.zzz", title: "Kullanılmayan uygulamalar",
                        detail: uninstaller.apps.isEmpty ? "Kategorilere bak" : "\(uninstaller.count(.unneeded)) uygulama · \(Format.bytes(uninstaller.size(.unneeded)))") {
                uninstaller.tab = .apps
                uninstaller.category = .unneeded
                state.go(.uninstaller)
            }
            QuickAction(icon: "doc.on.doc", title: "Kopya dosyalar", detail: state.duplicates.hasScanned ? Format.bytes(state.duplicates.foundSize) + " boşa" : "Aynı dosyaları bul") {
                state.go(.duplicates)
            }
            QuickAction(icon: "folder.badge.minus", title: "Proje klasörleri", detail: state.folders.hasScanned ? Format.bytes(state.folders.foundSize) : "node_modules, boş klasörler") {
                state.go(.folders)
            }
            QuickAction(icon: "heart.text.square", title: "Mac Sağlığı",
                        detail: state.health.battery.map { "Pil sağlığı %\($0.healthPercent) · tek tıkla optimize" } ?? "Pil, güvenlik, optimize") {
                state.go(.health)
            }
        }
    }

    // MARK: - Alt bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if let last = HistoryStore.shared.lastRestorable {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.inkMuted)
                Text("Son temizlik: \(Format.bytes(last.totalSize)) · \(Format.relative(last.date))").font(.label(12)).foregroundStyle(Theme.inkMuted)
                PillButton(title: "Geri al", icon: "arrow.uturn.backward", style: .muted, compact: true) {
                    let r = HistoryStore.shared.restore(last)
                    state.showToast("\(r.restored) öğe geri yüklendi")
                }
            } else {
                Image(systemName: "keyboard").foregroundStyle(Theme.inkMuted)
                Text("Kısayollar: ⌘↩ tara/temizle · ⌘1–9 bölümler · Esc ana sayfa · ⌘[ geri").font(.label(11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private func scanAll() async {
        scanning = true
        async let a: Void = junk.scan()
        async let b: Void = large.scan()
        async let c: Void = uninstaller.scanOrphans()
        async let d: Void = speed.load()
        _ = await (a, b, c, d)
        disk = SystemInfo.disk()
        scanning = false
    }

    private func clean() async {
        cleaning = true
        let items = cleanable
        let outcome = await state.clean(items, module: .smartScan)
        let removed = Set(outcome.record.files.map { URL(fileURLWithPath: $0.original) })
        for model in [junk, large] as [ScanModel] {
            for i in model.result.groups.indices { model.result.groups[i].items.removeAll { removed.contains($0.url) } }
            model.result.groups.removeAll { $0.items.isEmpty }
            model.selection.subtract(removed)
        }
        withAnimation(.spring(duration: 1.2)) { disk = SystemInfo.disk() }
        cleaning = false
        await speed.load()
    }
}

private struct ModuleCard: View {
    let title: String
    let subtitle: String
    let bytes: Int64?
    let spark: [Double]
    let busy: Bool
    let open: () -> Void

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 16))
                        Text(subtitle).font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    CircleIconButton(icon: "arrow.up.right", size: 32, action: open)
                }
                Spacer(minLength: 0)
                if busy {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.pillMuted).frame(height: 40).shimmer()
                } else if let bytes {
                    WaveSparkline(values: spark.count >= 2 ? spark : [0, Double(max(bytes, 1)), 0])
                        .frame(maxHeight: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Bulunan").font(.label(11)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if let bytes { BytesText(bytes: bytes, size: 24) } else { Text("—").font(.display(24)).foregroundStyle(Theme.inkMuted) }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .hoverLift()
        .animation(.spring(duration: 0.4), value: busy)
    }
}

private struct SpeedCard: View {
    @ObservedObject var model: SpeedUpModel
    let open: () -> Void

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hızlandırma").font(.system(size: 16))
                        Text(model.loaded ? "\(model.checks.filter { $0.level != .good }.count) öneri" : "Sağlık ve başlangıç").font(.label(10)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    CircleIconButton(icon: "arrow.up.right", size: 32, action: open)
                }
                Spacer(minLength: 0)
                if model.isLoading && !model.loaded {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.pillMuted).frame(height: 40).shimmer()
                } else if model.loaded {
                    let issues = model.checks.filter { $0.level != .good }
                    VStack(alignment: .leading, spacing: 4) {
                        if issues.isEmpty {
                            Label("Her şey yolunda", systemImage: "checkmark.circle").font(.label(11))
                        }
                        ForEach(issues.prefix(2)) { c in
                            HStack(spacing: 6) {
                                Circle().fill(c.level == .bad ? Theme.danger : Theme.accent).frame(width: 6, height: 6)
                                Text(c.title).font(.label(10)).lineLimit(1)
                            }
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Sağlık").font(.label(11)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text(model.loaded ? "\(model.score)" : "—").font(.display(24)).contentTransition(.numericText())
                    Text("/ 100").font(.label(10))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .hoverLift()
    }
}

private struct QuickAction: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AccentBadge(icon: icon, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.label(12)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 10).frame(height: 54)
            .background(Capsule().fill(Theme.surfaceRaised))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .hoverLift()
    }
}
