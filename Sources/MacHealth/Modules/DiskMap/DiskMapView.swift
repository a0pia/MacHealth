import AppKit
import SwiftUI

/// Bir klasörün alt öğelerinin boyutlarını arka planda, iptal edilebilir şekilde hesaplar.
private final class SizeJob: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CleanItem] = []
    private var dirs: Set<URL> = []
    private var done = 0
    private var cancelled = false
    private var finished = false
    let total: Int

    init(total: Int) { self.total = total }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    func add(_ item: CleanItem?, isDir: Bool) {
        lock.lock()
        if let item {
            items.append(item)
            if isDir { dirs.insert(item.url) }
        }
        done += 1
        lock.unlock()
    }

    func finish() { lock.lock(); finished = true; lock.unlock() }

    func snapshot() -> (items: [CleanItem], dirs: Set<URL>, done: Int, finished: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (items.sorted { $0.size > $1.size }, dirs, done, finished)
    }
}

@MainActor
final class DiskMapModel: ObservableObject {
    @Published private(set) var path: [URL] = [SafetyGuard.home]
    @Published private(set) var nodes: [CleanItem] = []
    @Published private(set) var dirs: Set<URL> = []
    @Published private(set) var isLoading = false
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var accessDenied = false
    @Published var hovered: URL?

    private var cache: [URL: (items: [CleanItem], dirs: Set<URL>)] = [:]
    private var job: SizeJob?

    var current: URL { path.last! }
    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    /// Klasörü yükler. Ekran durumu senkron güncellenir (tıklandığı anda yeni klasöre geçer);
    /// boyutlar arka planda hesaplanır. Bitmesini beklemek için `.value` kullan.
    @discardableResult
    func load(force: Bool = false) -> Task<Void, Never> {
        let url = current
        job?.cancel()
        job = nil
        hovered = nil
        accessDenied = false

        if Demo.isOn {
            let map: (items: [CleanItem], dirs: Set<URL>) = url == SafetyGuard.home ? Demo.homeMap : ([], [])
            nodes = map.items; dirs = map.dirs; isLoading = false
            return Task {}
        }

        if !force, let cached = cache[url] {
            withAnimation(.spring(duration: 0.35)) {
                nodes = cached.items
                dirs = cached.dirs
                isLoading = false
            }
            return Task {}
        }

        // Veri kapları Tam Disk Erişimi olmadan ölçülemez (her biri ayrı izin sorusu açar).
        let blocked = !Permissions.hasFullDiskAccess && (Permissions.isAppContainer(url) || Permissions.containsAppContainers(url) && url.path.hasSuffix("Containers"))
        guard !blocked, let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            withAnimation { nodes = []; dirs = []; isLoading = false; accessDenied = true }
            return Task {}
        }
        let urls = names.filter { $0 != ".DS_Store" }.map { url.appendingPathComponent($0) }
        let job = SizeJob(total: urls.count)
        self.job = job
        nodes = []
        dirs = []
        progress = (0, urls.count)
        isLoading = true

        Task.detached(priority: .userInitiated) {
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                guard !job.isCancelled else { job.add(nil, isDir: false); return }
                let u = urls[i]
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
                let isDir = v?.isDirectory == true && v?.isPackage != true && v?.isSymbolicLink != true
                let s = FileSizer.size(of: u, isCancelled: { job.isCancelled })
                job.add(s > 0 ? CleanItem(url: u, size: s, modified: FileSizer.modified(u)) : nil, isDir: isDir)
            }
            job.finish()
        }

        // Sonuçları geldikçe göster
        return Task { await self.poll(job, url: url) }
    }

    private func poll(_ job: SizeJob, url: URL) async {
        while true {
            try? await Task.sleep(for: .milliseconds(300))
            guard self.job === job else { return }   // başka klasöre geçildi
            let snap = job.snapshot()
            withAnimation(.spring(duration: 0.35)) {
                nodes = snap.items
                dirs = snap.dirs
                progress = (snap.done, job.total)
            }
            if snap.finished {
                cache[url] = (snap.items, snap.dirs)
                withAnimation { isLoading = false }
                self.job = nil
                return
            }
        }
    }

    func isDirectory(_ url: URL) -> Bool { dirs.contains(url) }

    func open(_ item: CleanItem) {
        guard item.url != current else { return }
        guard isDirectory(item.url) else {
            QuickLook.show(item.url)
            return
        }
        path.append(item.url)
        load()
    }

    func go(to index: Int) {
        guard index < path.count - 1 else { return }
        path = Array(path.prefix(index + 1))
        load()
    }

    func up() {
        if path.count > 1 {
            go(to: path.count - 2)
        } else {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return }
            path = [parent]
            load()
        }
    }

    /// Verilen klasörü, ana klasörden başlayan yol ile açar (ör. Ana Sayfa'dan "Android SDK").
    func show(_ url: URL) {
        let home = SafetyGuard.home
        if url.path.hasPrefix(home.path + "/") {
            var p = [home]
            var cur = home
            for comp in url.path.dropFirst(home.path.count + 1).split(separator: "/") {
                cur = cur.appendingPathComponent(String(comp))
                p.append(cur)
            }
            path = p
        } else {
            path = [url]
        }
        load()
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Haritala"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = [url]
        load()
    }

    /// Başka bir modülde temizlik yapıldığında boyutlar değişir.
    func invalidateCache() {
        cache = [:]
    }

    func removed(_ urls: Set<URL>) {
        nodes.removeAll { urls.contains($0.url) }
        // Üst klasörlerin boyutları değişti; önbelleği temizle.
        cache = [:]
        cache[current] = (nodes, dirs)
    }
}

struct DiskMapView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: DiskMapModel
    @State private var pendingDelete: CleanItem?
    /// Alttaki bilgi şeridinde gösterilen öğe. Fare kutuların üzerinden geçerken her kutuda değişmesin diye
    /// kısa bir beklemeyle güncellenir ve fare ayrılınca son bilgi kalır (şeritteki butonlara ulaşılabilsin).
    @State private var infoURL: URL?

    private let maxTiles = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CircleIconButton(icon: "chevron.up", size: 34, help: "Üst klasör") { model.up() }
                breadcrumb
                Spacer()
                StatBlock(label: model.isLoading ? "Hesaplanıyor" : "Bu klasör",
                          value: Format.bytesSplit(model.total).0, unit: Format.bytesSplit(model.total).1)
                    .padding(.trailing, 12)
                PillButton(title: "Klasör seç", icon: "folder", style: .raised, compact: true) { model.chooseRoot() }
                CircleIconButton(icon: "arrow.clockwise", size: 34, help: "Yenile") { model.load(force: true) }
            }

            if model.isLoading {
                HStack(spacing: 10) {
                    CapsuleBar(fraction: model.progress.total > 0 ? Double(model.progress.done) / Double(model.progress.total) : 0,
                               fill: Theme.ink, track: Theme.surfaceRaised, height: 6)
                        .animation(.easeOut, value: model.progress.done)
                    Text("\(model.progress.done) / \(model.progress.total) öğe hesaplandı · büyük klasörler biraz sürebilir")
                        .font(.label(11)).foregroundStyle(Theme.inkMuted).fixedSize()
                }
                .transition(.opacity)
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface)
                    if model.accessDenied {
                        VStack(spacing: 14) {
                            EmptyStateView(icon: "lock", title: "Bu klasöre erişilemedi",
                                           message: "macOS bu klasörü koruyor. İçeriğini görmek için MacHealth'e Tam Disk Erişimi ver.")
                            PillButton(title: "İzin ver", icon: "lock.open", style: .dark) { Permissions.requestFullDiskAccess() }
                                .padding(.bottom, 40)
                        }
                    } else if model.nodes.isEmpty && model.isLoading {
                        ScanningPlaceholder(text: "Klasör boyutları hesaplanıyor", icon: "square.grid.3x3.square")
                    } else if model.nodes.isEmpty {
                        EmptyStateView(icon: "folder", title: "Bu klasör boş", message: "Gösterilecek dosya ya da klasör yok.")
                    } else {
                        treemap.padding(10)
                    }
                }
                sidePanel.frame(width: 310)
            }

            infoBar
        }
        .task { if model.nodes.isEmpty && !model.isLoading { await model.load().value } }
        .task(id: model.hovered) {
            guard let h = model.hovered, h != infoURL, Knowledge.folder(h) != nil else { return }
            try? await Task.sleep(for: .milliseconds(280))
            if !Task.isCancelled { infoURL = h }
        }
        .onChange(of: model.current) { _, _ in infoURL = nil }
        .confirmationDialog("Çöp Kutusu'na taşınsın mı?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            if let item = pendingDelete {
                Button("\(item.name) (\(Format.bytes(item.size))) Çöp'e taşı", role: .destructive) {
                    Task {
                        let outcome = await app.clean([item], module: .diskMap)
                        model.removed(Set(outcome.record.files.map { URL(fileURLWithPath: $0.original) }))
                    }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            if let item = pendingDelete, let info = Knowledge.folder(item.url)?.insight ?? Knowledge.item(item) {
                Text(info.consequences.joined(separator: "\n"))
            } else {
                Text("Geçmiş ekranından geri alabilirsin.")
            }
        }
    }

    private var breadcrumb: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(model.path.enumerated()), id: \.offset) { i, url in
                        if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.inkMuted) }
                        PillButton(title: i == 0 ? LargeFilesScanner.shortPath(url) : url.lastPathComponent,
                                   style: i == model.path.count - 1 ? .dark : .muted, compact: true) { model.go(to: i) }
                            .id(i)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: model.path.count) { _, n in withAnimation { proxy.scrollTo(n - 1, anchor: .trailing) } }
        }
    }

    // MARK: - Treemap

    /// En büyük öğeler + geri kalanı tek "Diğer" kutusunda.
    private var tiles: [(item: CleanItem, isOther: Bool)] {
        let nodes = model.nodes
        guard nodes.count > maxTiles else { return nodes.map { ($0, false) } }
        let rest = nodes.dropFirst(maxTiles - 1)
        let other = CleanItem(url: model.current.appendingPathComponent(".machealth-other"),
                              name: "Diğer \(rest.count) öğe", size: rest.reduce(0) { $0 + $1.size })
        return nodes.prefix(maxTiles - 1).map { ($0, false) } + [(other, true)]
    }

    private var treemap: some View {
        GeometryReader { geo in
            let shown = tiles
            let rects = Treemap.layout(shown.map { Double($0.item.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.item.id) { i, tile in
                    let r = rects[i].insetBy(dx: 3, dy: 3)
                    if r.width > 2 && r.height > 2 {
                        TreemapTile(node: tile.item, rank: tile.isOther ? 99 : i, rect: r,
                                    hovered: model.hovered == tile.item.url,
                                    isFolder: model.isDirectory(tile.item.url), isOther: tile.isOther,
                                    hasInfo: Knowledge.folder(tile.item.url) != nil,
                                    deletable: !tile.isOther && SafetyGuard.isDeletable(tile.item.url),
                                    onDelete: { pendingDelete = tile.item })
                            .onHover { inside in
                                if inside { model.hovered = tile.item.url } else if model.hovered == tile.item.url { model.hovered = nil }
                            }
                            .onTapGesture { if !tile.isOther { model.open(tile.item) } }
                            .contextMenu { if !tile.isOther { contextMenu(tile.item) } }
                    }
                }
            }
        }
    }

    // MARK: - Sağ panel

    private var sidePanel: some View {
        VStack(spacing: 12) {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("En büyükler").font(.label(11)).foregroundStyle(Theme.inkMuted).padding(.leading, 6).padding(.bottom, 4)
                    AdaptiveScroll {
                        VStack(spacing: 2) {
                            ForEach(model.nodes.prefix(60)) { node in
                                listRow(node)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Bilgi şeridi

    /// Sayfanın altında sabit yükseklikte bilgi şeridi; içeriği değişse de düzen kaymaz.
    private var infoBar: some View {
        let url = infoURL ?? model.current
        let info = Knowledge.folder(url)
        return HStack(spacing: 12) {
            if let info {
                ZStack {
                    Circle().fill(info.insight.risk == .safe ? Theme.success.opacity(0.35) : info.insight.risk.color)
                    Image(systemName: "info").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(info.insight.risk == .caution ? .white : Theme.ink)
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(url == model.current ? "Bu klasör nedir?" : "\(url.lastPathComponent) nedir?")
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        RiskBadge(risk: info.insight.risk)
                    }
                    Text(info.insight.what).font(.label(11)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if let target = info.action {
                    PillButton(title: "\(target.title) bölümüne git", icon: target.icon, style: .accent, compact: true) { app.go(target) }
                }
                InfoButton(insight: info.insight)
                if infoURL != nil && infoURL != model.current {
                    MiniIcon(icon: "xmark", help: "Bu klasörün bilgisine dön") { infoURL = nil }
                }
            } else {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(Theme.inkMuted).frame(width: 24)
                Text("Yanında \(Image(systemName: "info.circle.fill")) olan kutuların üzerine gel; ne olduklarını ve silersen ne olacağını burada görürsün.")
                    .font(.label(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .animation(nil, value: infoURL)
    }

    private func listRow(_ node: CleanItem) -> some View {
        let frac = model.total > 0 ? Double(node.size) / Double(model.total) : 0
        let isDir = model.isDirectory(node.url)
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(node.name).font(.label(12)).lineLimit(1).truncationMode(.middle)
                    if Knowledge.folder(node.url) != nil {
                        Image(systemName: "info.circle.fill").font(.system(size: 9)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    Text(Format.bytes(node.size)).font(.label(11)).foregroundStyle(Theme.inkMuted)
                }
                CapsuleBar(fraction: frac, fill: model.hovered == node.url ? Theme.ink : Theme.accent, height: 4)
            }
            if model.hovered == node.url {
                if SafetyGuard.isDeletable(node.url) {
                    MiniIcon(icon: "trash", help: "Çöp'e taşı") { pendingDelete = node }
                } else {
                    Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.inkMuted).frame(width: 26).help("Korumalı konum")
                }
            } else {
                Image(systemName: isDir ? "chevron.right" : "eye").font(.system(size: 9)).foregroundStyle(Theme.inkMuted).frame(width: 26)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(model.hovered == node.url ? Theme.surfaceRaised : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hovered = node.url } else if model.hovered == node.url { model.hovered = nil }
        }
        .onTapGesture { model.open(node) }
        .contextMenu { contextMenu(node) }
        .help(isDir ? "Klasörü aç" : "Önizle")
    }

    @ViewBuilder
    private func contextMenu(_ node: CleanItem) -> some View {
        if model.isDirectory(node.url) { Button("Aç") { model.open(node) } }
        Button("Finder'da göster") { SystemActions.revealInFinder(node.url) }
        Button("Önizle") { QuickLook.show(node.url) }
        Divider()
        if SafetyGuard.isDeletable(node.url) {
            Button("Çöp'e taşı…") { pendingDelete = node }
        } else {
            Text("Korumalı konum")
        }
    }
}

private struct TreemapTile: View {
    let node: CleanItem
    let rank: Int
    let rect: CGRect
    let hovered: Bool
    let isFolder: Bool
    let isOther: Bool
    let hasInfo: Bool
    var deletable = false
    var onDelete: () -> Void = {}

    private var fill: Color {
        if isOther { return Theme.pillMuted }
        if hovered { return Theme.ink }
        switch rank {
        case 0: return Theme.accent
        case 1, 2: return Color(hex: 0xF7FCA0)
        default: return [Color(hex: 0xFFFFFF), Color(hex: 0xE4E5DE), Color(hex: 0xD7D8D0)][rank % 3]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(18, min(rect.width, rect.height) / 3), style: .continuous)
                .fill(fill)
                .overlay {
                    if isOther {
                        RoundedRectangle(cornerRadius: min(18, min(rect.width, rect.height) / 3), style: .continuous)
                            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
            if rect.width > 70 && rect.height > 40 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: isOther ? "ellipsis" : (isFolder ? "folder" : "doc")).font(.system(size: 9))
                        Text(node.name).font(.label(11)).lineLimit(1)
                        if hasInfo { Image(systemName: "info.circle.fill").font(.system(size: 9)).opacity(0.6) }
                    }
                    Text(Format.bytes(node.size)).font(.display(rect.width > 160 && rect.height > 80 ? 20 : 13))
                }
                .foregroundStyle(hovered && !isOther ? .white : Theme.ink)
                .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovered && deletable && rect.width > 60 && rect.height > 50 {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .help("Çöp'e taşı")
                .padding(6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .help(isOther ? node.name : "\(node.name) — \(Format.bytes(node.size))\(isFolder ? " · açmak için tıkla" : " · önizlemek için tıkla")")
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
