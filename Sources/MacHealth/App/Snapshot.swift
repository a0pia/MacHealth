import AppKit
import SwiftUI

/// Geliştirici aracı: `MacHealth --snapshot <klasör> [modül…]` her modülü PNG olarak çizer ve çıkar.
/// Not: ImageRenderer bazı AppKit kontrollerini (kaydırma alanı, anahtar) çizemez; düzen kontrolü içindir.
@MainActor
enum Snapshot {
    static var snapSize = CGSize(width: 1360, height: 860)

    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--report") { report(); return }
        if args.contains("--selftest") { selfTest(); return }
        if let i = args.firstIndex(of: "--layer-test"), i + 1 < args.count { layerTest(URL(fileURLWithPath: args[i + 1])); return }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = Set(args.dropFirst(i + 2).filter { !$0.contains("x") || Module(rawValue: $0) != nil })
        if let sz = args.dropFirst(i + 2).first(where: { $0.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil }) {
            let parts = sz.split(separator: "x").compactMap { Double($0) }
            snapSize = CGSize(width: parts[0], height: parts[1])
        }
        let modules = Module.allCases.filter { names.isEmpty || names.contains($0.rawValue) }

        Task { @MainActor in
            let state = AppState()
            // Taramalı modüllerin sonuçlarını önceden doldur.
            if names.contains("scan") || names.isEmpty {
                await state.junk.scan()
                await state.speedUp.load()
                await state.uninstaller.load()
                await state.diskMap.load().value
                await state.folders.scan()
                await state.duplicates.scan()
                state.folders.expanded = ["devFolders"]
                await state.health.load()
                if let first = state.uninstaller.apps.max(by: { $0.size < $1.size }) { state.uninstaller.select(first) }
                state.junk.expanded = ["userCaches"]
            }
            for m in modules {
                state.go(m)
                state.memory.refresh()
                try? await Task.sleep(for: .milliseconds(1500))
                let view = MainWindow()
                    .environmentObject(state)
                    .environmentObject(HistoryStore.shared)
                    .frame(width: snapSize.width, height: snapSize.height)
                    .preferredColorScheme(.light)
                    .environment(\.snapshotMode, true)
                let r = ImageRenderer(content: view)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(m.rawValue).png"))
                }
            }
            // Ek görünümler: logo, temizlik özeti, kutlama
            @MainActor func save<V: View>(_ v: V, _ name: String, scale: CGFloat = 1) {
                let r = ImageRenderer(content: v.environment(\.snapshotMode, true))
                r.scale = scale
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent(name))
                }
            }
            save(LogoMark(size: 256, iconPadding: true), "logo.png")
            save(MenuBarPanel().environmentObject(state), "menubar.png")
            let icon = MenuBarIcon.image
            print("menü çubuğu simgesi: \(icon.size) şablon=\(icon.isTemplate) temsil=\(icon.representations.map { "\(type(of: $0)) \($0.pixelsWide)px" })")
            if let tiff = icon.tiffRepresentation { try? tiff.write(to: dir.appendingPathComponent("menubar-icon.tiff")) }
            save(OptimizeSheet(runner: OptimizeRunner(firewallOff: true)).environmentObject(state), "optimize.png")
            save(CleanSummarySheet(title: "Temizlik özeti", lines: CleanSummarySheet.Line.from(state.junk)) {}, "summary.png")
            state.go(.smartScan)
            state.celebration = 12_400_000_000
            try? await Task.sleep(for: .milliseconds(900))
            save(MainWindow().environmentObject(state).environmentObject(HistoryStore.shared).frame(width: snapSize.width, height: snapSize.height), "celebration.png")
            NSApp.terminate(nil)
        }
    }

    /// `MacHealth --report`: tarama sonuçlarını terminale yazar (hiçbir şey silmez).
    static func report() {
        Task.detached {
            for (name, r) in [("SİSTEM ÇÖPÜ", JunkScanner.scan()), ("BÜYÜK DOSYALAR", LargeFilesScanner.scan(.init()))] {
                print("== \(name): \(Format.bytes(r.totalSize)) · varsayılan seçim \(r.defaultSelection.count) öğe")
                for g in r.groups {
                    print("  \(g.title): \(Format.bytes(g.totalSize)) (\(g.items.count) öğe, varsayılan seçili: \(g.selectedByDefault))")
                    for i in g.items.prefix(6) { print("     \(Format.bytes(i.size))\t\(i.name)\(i.caution.map { " [\($0)]" } ?? "")") }
                }
                if !r.deniedPaths.isEmpty { print("  Erişilemeyen: \(r.deniedPaths)") }
            }
            var t = Date()
            let dup = DuplicatesScanner.scan()
            let wasted = dup.groups.reduce(Int64(0)) { $0 + $1.items.dropFirst().reduce(0) { $0 + $1.size } }
            print("== KOPYALAR: \(dup.groups.count) grup, \(Format.bytes(wasted)) boşa (\(String(format: "%.1f", Date().timeIntervalSince(t))) sn)")
            for g in dup.groups.prefix(5) { print("     \(g.note)\t\(g.title)") }
            t = Date()
            let folders = FoldersScanner.scan()
            print("== KLASÖRLER: \(Format.bytes(folders.totalSize)) (\(String(format: "%.1f", Date().timeIntervalSince(t))) sn)")
            for g in folders.groups {
                print("  \(g.title): \(Format.bytes(g.totalSize)) (\(g.items.count) öğe)")
                for i in g.items.prefix(6) { print("     \(Format.bytes(i.size))\t\(i.name)\(i.caution.map { " [\($0)]" } ?? "")") }
            }
            var apps = AppScanner.installedApps()
            for i in apps.indices {
                apps[i].size = FileSizer.size(of: apps[i].url)
                apps[i].dataSize = AppScanner.leftovers(for: apps[i]).reduce(0) { $0 + $1.size }
            }
            print("== DİSKİNİ NELER DOLDURUYOR?")
            for h in SpaceInsightsModel.scan(apps: apps) { print("     \(Format.bytes(h.size))\t\(h.title) — \(h.detail)") }
            print("== UYGULAMALAR: " + AppCategory.allCases.map { c in "\(c.title) \(apps.filter { $0.category == c }.count)" }.joined(separator: " · "))
            for a in apps.sorted(by: { $0.totalSize > $1.totalSize }).prefix(8) { print("     [\(a.category.title)] \(a.name): uygulama \(Format.bytes(a.size)) + veri \(Format.bytes(a.dataSize))") }
            let orphans = AppScanner.orphans(installed: apps)
            print("== SAHİPSİZ ARTIKLAR: \(Format.bytes(orphans.reduce(0) { $0 + $1.size })) (\(orphans.count) öğe)")
            for o in orphans.prefix(10) { print("     \(Format.bytes(o.size))\t\(o.name)\t\(o.detail ?? "")") }
            let startup = StartupService.list()
            print("== BAŞLANGIÇ: \(startup.count) öğe")
            for s in startup { print("     \(s.enabled ? "●" : "○") \(s.label) (\(s.scope.rawValue))") }
            await MainActor.run { NSApp.terminate(nil) }
        }
    }

    /// `MacHealth --selftest`: Disk Haritası gezinme senaryosu (hiçbir şey silmez).
    static func selfTest() {
        Task { @MainActor in
            let m = DiskMapModel()
            var ok = true
            func check(_ cond: Bool, _ msg: String) { print((cond ? "  ✓ " : "  ✗ ") + msg); if !cond { ok = false } }
            let t0 = Date()
            await m.load().value
            print("Ana klasör: \(m.nodes.count) öğe, \(String(format: "%.1f", Date().timeIntervalSince(t0))) sn")
            guard let lib = m.nodes.first(where: { $0.url.lastPathComponent == "Library" }) else { print("Library yok"); exit(1) }
            check(m.isDirectory(lib.url), "Library klasör olarak tanındı")

            // Library'e tıkla; hesap sürerken bir daha tıkla (eski hata: yol iki kez eklenirdi)
            m.open(lib)
            check(m.nodes.isEmpty && m.isLoading, "Tıklandığı anda eski içerik temizlendi, yükleniyor gösteriliyor")
            try? await Task.sleep(for: .milliseconds(400))
            check(m.nodes.allSatisfy { $0.url.deletingLastPathComponent() == lib.url }, "Tıklayınca ekran hemen Library içeriğine geçti (eski klasör kalmadı)")
            m.open(lib)
            check(m.path.count == 2, "İkinci tıklama yolu çoğaltmadı (yol: \(m.path.map(\.lastPathComponent)))")
            check(m.isLoading, "Yükleniyor göstergesi açık (\(m.progress.done)/\(m.progress.total))")

            // Hesap sürerken geri dön → önbellekten anında gelmeli, yükleme durmalı
            m.go(to: 0)
            check(!m.isLoading, "Geri dönünce yükleme iptal edildi, gösterge kapandı")
            check(m.nodes.contains { $0.url == lib.url }, "Ana klasör önbellekten anında geldi")

            // Tekrar Library'e gir ve sonuna kadar bekle
            let t1 = Date()
            m.open(lib)
            var firstPartial: Double?
            while m.isLoading {
                try? await Task.sleep(for: .milliseconds(200))
                if firstPartial == nil && !m.nodes.isEmpty { firstPartial = Date().timeIntervalSince(t1) }
            }
            print("Library: \(m.nodes.count) öğe, ilk sonuçlar \(String(format: "%.1f", firstPartial ?? 0)) sn, tamamı \(String(format: "%.1f", Date().timeIntervalSince(t1))) sn")
            check(m.path.count == 2 && m.current == lib.url, "Library'de")
            check(!m.nodes.isEmpty && m.nodes.allSatisfy { $0.url.deletingLastPathComponent() == lib.url }, "Library içeriği listelendi (ana klasörün değil)")
            print("  En büyükler: " + m.nodes.prefix(4).map { "\($0.name) \(Format.bytes($0.size))" }.joined(separator: ", "))
            if let file = m.nodes.first(where: { !m.isDirectory($0.url) }) {
                print("  (dosya örneği: \(file.name) — tıklayınca Quick Look açılır, klasör sanılmaz)")
            }
            m.up()
            check(m.path.count == 1, "Üst klasör butonu çalıştı")
            print(ok ? "SONUÇ: tüm kontroller geçti" : "SONUÇ: HATA VAR")
            exit(ok ? 0 : 1)
        }
    }

    /// Core Animation tabanlı görünümleri PNG'ye çizer (ImageRenderer bunları çizemez).
    static func layerTest(_ out: URL) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(Theme.surface).cgColor
        let g = LiquidGaugeView(frame: NSRect(x: 15, y: 15, width: 170, height: 170))
        g.update(fraction: 0.7, live: false)
        host.addSubview(g)
        let p = PulseRingView(frame: NSRect(x: 220, y: 20, width: 160, height: 160))
        p.update(color: Theme.ink, live: false, bleed: 40)
        host.addSubview(p)
        host.layoutSubtreeIfNeeded(); g.layout(); p.layout()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 420, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.setFillColor(NSColor(Theme.surface).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 420, height: 200))
        func dump(_ l: CALayer, _ d: Int) {
            print(String(repeating: "  ", count: d) + "\(type(of: l)) frame=\(l.frame) mask=\(l.mask != nil)")
            l.sublayers?.forEach { dump($0, d + 1) }
        }
        for v in [g, p as NSView] {
            guard let l = v.layer else { print("katman yok"); continue }
            dump(l, 0)
            ctx.saveGState()
            ctx.translateBy(x: v.frame.minX, y: v.frame.minY)
            l.render(in: ctx)
            ctx.restoreGState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: out)
        exit(0)
    }
}
