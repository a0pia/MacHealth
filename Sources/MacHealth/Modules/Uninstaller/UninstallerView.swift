import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class UninstallerModel: ObservableObject {
    enum Tab { case apps, orphans }
    enum Sort: String, CaseIterable { case size = "Boyut", lastUsed = "Son kullanım", name = "İsim" }

    @Published var tab: Tab = .apps
    @Published var apps: [AppInfo] = []
    @Published var isLoading = false
    @Published var search = ""
    @Published var sort: Sort = .size
    @Published var category: AppCategory? = nil
    @Published var genre: String? = nil

    @Published var selectedApp: AppInfo?
    @Published var leftovers: [CleanItem] = []
    @Published var leftoverSelection: Set<URL> = []
    @Published var loadingLeftovers = false

    @Published var orphans: [CleanItem] = []
    @Published var orphanSelection: Set<URL> = []
    @Published var loadingOrphans = false
    @Published var orphansScanned = false

    var visibleApps: [AppInfo] {
        var list = apps
        if !search.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        if let category { list = list.filter { $0.category == category } }
        if let genre { list = list.filter { $0.genre == genre } }
        switch sort {
        case .name: break
        case .size: list.sort { $0.totalSize > $1.totalSize }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    var genres: [String] { Array(Set(apps.compactMap(\.genre))).sorted() }
    func count(_ c: AppCategory) -> Int { apps.filter { $0.category == c }.count }
    func size(_ c: AppCategory) -> Int64 { apps.filter { $0.category == c }.reduce(0) { $0 + $1.totalSize } }
    var unusedCount: Int { count(.unneeded) }

    /// Listeyi baştan okur (yeni kurulan / silinen uygulamalar için).
    func reload() async {
        guard !isLoading else { return }
        apps = []
        await load()
    }

    func load() async {
        guard apps.isEmpty, !isLoading else { return }
        isLoading = true
        let list = await Task.detached(priority: .userInitiated) { AppScanner.installedApps() }.value
        apps = list
        isLoading = false
        // Boyutları arka planda hesapla
        let sized = await Task.detached(priority: .utility) {
            var sizes = [Int64](repeating: 0, count: list.count)
            var data = [Int64](repeating: 0, count: list.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: list.count) { i in
                let s = FileSizer.size(of: list[i].url)
                // Uygulamanın Library'deki verileri (ör. WhatsApp sohbet medyası)
                let d = AppScanner.leftovers(for: list[i]).reduce(Int64(0)) { $0 + $1.size }
                lock.lock(); sizes[i] = s; data[i] = d; lock.unlock()
            }
            var out = list
            for i in out.indices { out[i].size = sizes[i]; out[i].dataSize = data[i] }
            return out
        }.value
        withAnimation { apps = sized }
        if let sel = selectedApp, let updated = sized.first(where: { $0.url == sel.url }) { selectedApp = updated }
    }

    func select(_ app: AppInfo) {
        withAnimation(.spring(duration: 0.3)) { selectedApp = app }
        leftovers = []
        leftoverSelection = []
        loadingLeftovers = true
        Task {
            let items = await Task.detached { AppScanner.leftovers(for: app) }.value
            guard selectedApp?.url == app.url else { return }
            withAnimation {
                leftovers = items
                leftoverSelection = Set(items.filter { $0.caution == nil }.map(\.url))
                loadingLeftovers = false
            }
        }
    }

    func selectDropped(_ url: URL) {
        if let existing = apps.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            select(existing)
        } else if var info = AppScanner.info(for: url) {
            info.size = FileSizer.size(of: url)
            apps.append(info)
            select(info)
        }
        tab = .apps
    }

    func scanOrphans() async {
        loadingOrphans = true
        if apps.isEmpty { await load() }
        let installed = apps
        let items = await Task.detached(priority: .userInitiated) { AppScanner.orphans(installed: installed) }.value
        withAnimation {
            orphans = items
            orphanSelection = Set(items.filter { $0.caution == nil }.map(\.url))
            loadingOrphans = false
            orphansScanned = true
        }
    }

    var leftoverSelectedSize: Int64 { leftovers.filter { leftoverSelection.contains($0.url) }.reduce(0) { $0 + $1.size } }
    var uninstallTotal: Int64 { (selectedApp?.size ?? 0) + leftoverSelectedSize }

    func isRunning(_ app: AppInfo) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
    }

    private func quitIfRunning(_ app: AppInfo) async {
        guard let running = isRunning(app) else { return }
        running.terminate()
        for _ in 0..<20 where !running.isTerminated { try? await Task.sleep(for: .milliseconds(150)) }
    }

    func uninstall(using state: AppState) async {
        guard let app = selectedApp, !app.isProtected else { return }
        await quitIfRunning(app)
        var items = [CleanItem(url: app.url, name: app.name, size: app.size)]
        items += leftovers.filter { leftoverSelection.contains($0.url) }
        let outcome = await state.clean(items, module: .uninstaller)
        if outcome.record.files.contains(where: { $0.original == app.url.path }) {
            withAnimation(.spring(duration: 0.4)) {
                apps.removeAll { $0.url == app.url }
                selectedApp = nil
                leftovers = []
            }
        } else if let fail = outcome.failed.first(where: { $0.path == app.url.path }) {
            state.showToast("\(app.name) kaldırılamadı: \(fail.reason)")
        }
    }

    /// Uygulamayı bırakıp sadece ayar/önbellek dosyalarını siler.
    func reset(using state: AppState) async {
        guard let app = selectedApp else { return }
        await quitIfRunning(app)
        let items = leftovers.filter { leftoverSelection.contains($0.url) }
        let outcome = await state.clean(items, module: .uninstaller)
        let removed = Set(outcome.record.files.map(\.original))
        withAnimation {
            leftovers.removeAll { removed.contains($0.url.path) }
            leftoverSelection = Set(leftovers.map(\.url))
        }
    }

    func cleanOrphans(using state: AppState) async {
        let items = orphans.filter { orphanSelection.contains($0.url) }
        let outcome = await state.clean(items, module: .uninstaller)
        let removed = Set(outcome.record.files.map(\.original))
        withAnimation {
            orphans.removeAll { removed.contains($0.url.path) }
            orphanSelection = orphanSelection.filter { !removed.contains($0.path) }
        }
    }
}

struct UninstallerView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: UninstallerModel
    @State private var dropTargeted = false
    @State private var sheet: SheetKind?
    @ObservedObject private var perms = PermissionCenter.shared

    enum SheetKind: String, Identifiable { case uninstall, reset, orphans; var id: String { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                PillButton(title: "Uygulamalar", icon: "square.grid.2x2", style: model.tab == .apps ? .raised : .muted, compact: true) { withAnimation { model.tab = .apps } }
                PillButton(title: "Sahipsiz artıklar", icon: "questionmark.folder", style: model.tab == .orphans ? .raised : .muted, compact: true) { withAnimation { model.tab = .orphans } }
                Spacer()
                Text("İpucu: Finder'dan bir uygulamayı buraya sürükleyip bırakabilirsin")
                    .font(.label(11)).foregroundStyle(Theme.inkMuted)
                CircleIconButton(icon: "arrow.clockwise", size: 32, help: "Listeyi yenile") {
                    Task { if model.tab == .apps { await model.reload() } else { await model.scanOrphans() } }
                }
            }

            FullDiskAccessBanner(title: "Her uygulamada izin sorulmasın",
                                 message: "macOS her uygulamanın veri klasörü için ayrı izin ister. MacHealth'e bir kez Tam Disk Erişimi verirsen hepsi birden açılır; o zamana kadar bu klasörler atlanır.")
            if model.tab == .apps {
                categoryCards
                appsTab
            } else {
                orphansTab
            }
        }
        .task { await model.load() }
        .onChange(of: perms.fullDiskAccess) { _, granted in
            guard granted else { return }
            Task {
                await model.reload()
                if let app = model.selectedApp { model.select(app) }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                Task { @MainActor in model.selectDropped(url) }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.accent.opacity(0.3))
                    RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    VStack(spacing: 12) {
                        AccentBadge(icon: "arrow.down.app", size: 70).floating(6)
                        Text("Kaldırmak için uygulamayı bırak").font(.display(22))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .sheet(item: $sheet) { kind in sheetView(kind) }
    }

    // MARK: - Kategori kartları

    private var categoryCards: some View {
        HStack(spacing: 10) {
            ForEach(AppCategory.allCases, id: \.self) { c in
                let active = model.category == c
                Button { withAnimation(.spring(duration: 0.3)) { model.category = active ? nil : c } } label: {
                    HStack(spacing: 12) {
                        AccentBadge(icon: c.icon, size: 38, dimmed: c != .unneeded && !active)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.label(12)).foregroundStyle(active ? .white : Theme.ink)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(model.count(c))").font(.display(22))
                                Text("uygulama · \(Format.bytes(model.size(c)))").font(.label(10))
                                    .foregroundStyle(active ? .white.opacity(0.6) : Theme.inkMuted)
                            }
                            .foregroundStyle(active ? .white : Theme.ink)
                        }
                        Spacer()
                        if active { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)) }
                    }
                    .padding(.horizontal, 14).frame(height: 66)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(active ? Theme.inkDark : Theme.surface))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .hoverLift()
                .help(categoryHelp(c))
            }
        }
    }

    private func categoryHelp(_ c: AppCategory) -> String {
        switch c {
        case .unneeded: "6 aydan uzun süredir açılmamış ya da yüklendiğinden beri hiç açılmamış uygulamalar"
        case .occasional: "Son 1–6 ay içinde açılmış uygulamalar"
        case .essential: "Son 30 günde kullandığın uygulamalar ve sistem uygulamaları"
        }
    }

    // MARK: - Uygulamalar sekmesi

    private var appsTab: some View {
        HStack(spacing: 14) {
            Card(padding: 12) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        TextField("Uygulama ara", text: $model.search).textFieldStyle(.plain).font(.label(12))
                        if !model.search.isEmpty {
                            Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().fill(Theme.surfaceRaised))

                    HStack(spacing: 4) {
                        ForEach(UninstallerModel.Sort.allCases, id: \.self) { s in
                            PillButton(title: s.rawValue, style: model.sort == s ? .dark : .muted, compact: true) { withAnimation { model.sort = s } }
                        }
                        Spacer()
                        Menu {
                            Button("Tüm türler") { model.genre = nil }
                            Divider()
                            ForEach(model.genres, id: \.self) { g in Button(g) { model.genre = g } }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10))
                                Text(model.genre ?? "Tür").font(.label(11))
                            }
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Capsule().fill(model.genre == nil ? Theme.pillMuted : Theme.accent))
                    }

                    if model.isLoading {
                        ScanningPlaceholder(text: "Uygulamalar okunuyor", icon: "square.grid.2x2")
                    } else if model.visibleApps.isEmpty {
                        Text("Bu filtreye uyan uygulama yok.").font(.label(12)).foregroundStyle(Theme.inkMuted).frame(maxHeight: .infinity)
                    } else {
                        AdaptiveScroll {
                            LazyVStack(spacing: 2) {
                                ForEach(model.visibleApps) { app in
                                    AppRow(app: app, selected: model.selectedApp?.url == app.url) { model.select(app) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 370)

            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            ZStack(alignment: .bottom) {
                Card(padding: 22) {
                    AdaptiveScroll {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 16) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 68, height: 68)
                                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(app.name).font(.display(26))
                                        CategoryTag(category: app.category)
                                    }
                                    Text([app.genre, app.version.map { "Sürüm \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                                        .font(.label(11)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                                CircleIconButton(icon: "folder", size: 34, help: "Finder'da göster") { SystemActions.revealInFinder(app.url) }
                            }
                            HStack(spacing: 28) {
                                StatBlock(label: "Uygulama", value: Format.bytesSplit(app.size).0, unit: Format.bytesSplit(app.size).1)
                                let lsize = model.leftovers.reduce(0) { $0 + $1.size }
                                StatBlock(label: "Ayar ve veriler", value: Format.bytesSplit(lsize).0, unit: Format.bytesSplit(lsize).1)
                                StatBlock(label: "Son kullanım", value: app.lastUsed.map { Format.relative($0) } ?? "hiç açılmamış", size: 16)
                                StatBlock(label: "Yüklenme", value: Format.date(app.dateAdded), size: 16)
                            }

                            InfoBox(insight: app.recommendation, title: "Öneri")
                            if let tip = Knowledge.appData(bundleID: app.bundleID, name: app.name, dataSize: max(app.dataSize, model.leftovers.reduce(0) { $0 + $1.size })),
                               max(app.dataSize, model.leftovers.reduce(0) { $0 + $1.size }) > 200 * 1024 * 1024 {
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoBox(insight: tip, title: "Verileri nasıl küçültürsün?")
                                    PillButton(title: "\(app.name) uygulamasını aç", icon: "arrow.up.forward.app", style: .accent, compact: true) {
                                        NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
                                    }
                                }
                            }
                            if !app.isProtected, let i = Knowledge.group("uninstall") { InfoBox(insight: i) }

                            HStack {
                                Text("İlgili dosyalar").font(.label(11)).foregroundStyle(Theme.inkMuted)
                                Spacer()
                                if !model.leftovers.isEmpty && !app.isProtected {
                                    PillButton(title: "Sadece sıfırla", icon: "arrow.counterclockwise", style: .raised, compact: true) { sheet = .reset }
                                        .help("Uygulamayı silmeden ayarlarını ve önbelleğini temizle")
                                }
                            }
                            if model.loadingLeftovers {
                                ProgressView().controlSize(.small)
                            } else if model.leftovers.isEmpty {
                                Text("Library'de bu uygulamaya ait dosya bulunamadı.").font(.label(12)).foregroundStyle(Theme.inkMuted)
                            } else {
                                VStack(spacing: 2) {
                                    ForEach(model.leftovers) { item in
                                        ItemRow(item: item, selected: model.leftoverSelection.contains(item.url), showDate: false) {
                                            if model.leftoverSelection.contains(item.url) { model.leftoverSelection.remove(item.url) } else { model.leftoverSelection.insert(item.url) }
                                        }
                                    }
                                }
                            }
                            Color.clear.frame(height: 70)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .id(app.url)
                .transition(.opacity.combined(with: .offset(x: 12)))

                if !app.isProtected {
                    BottomActionBar(actionTitle: model.loadingLeftovers ? "Dosyalar aranıyor…" : "Kaldır", actionIcon: "xmark.app",
                                    enabled: !model.loadingLeftovers) {
                        HStack(spacing: 10) {
                            BytesText(bytes: model.uninstallTotal, size: 22)
                            Text("· uygulama + \(model.leftoverSelection.count) dosya").font(.label(12)).foregroundStyle(Theme.inkMuted)
                        }
                    } action: { sheet = .uninstall }
                    .padding(12)
                }
            }
        } else {
            Card {
                EmptyStateView(icon: "square.grid.2x2", title: "Bir uygulama seç",
                               message: "Soldan bir uygulama seç ya da Finder'dan sürükleyip bırak. Üstteki kartlarla kullanmadığın uygulamaları hızlıca bulabilirsin.")
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sheetView(_ kind: SheetKind) -> some View {
        switch kind {
        case .uninstall:
            let app = model.selectedApp
            CleanSummarySheet(title: "\(app?.name ?? "") kaldırılsın mı?", lines: [
                .init(id: "app", title: "Uygulama", icon: "app", count: 1, size: app?.size ?? 0, insight: Knowledge.group("uninstall")),
                .init(id: "leftovers", title: "Ayar, önbellek ve veri dosyaları", icon: "folder", count: model.leftoverSelection.count,
                      size: model.leftoverSelectedSize, insight: Knowledge.group("reset")),
            ].filter { $0.count > 0 }, actionTitle: "Kaldır") {
                Task { await model.uninstall(using: state) }
            }
        case .reset:
            CleanSummarySheet(title: "\(model.selectedApp?.name ?? "") sıfırlansın mı?", lines: [
                .init(id: "reset", title: "Ayar, önbellek ve veri dosyaları", icon: "arrow.counterclockwise",
                      count: model.leftoverSelection.count, size: model.leftoverSelectedSize, insight: Knowledge.group("reset")),
            ], actionTitle: "Sıfırla") {
                Task { await model.reset(using: state) }
            }
        case .orphans:
            let sel = model.orphans.filter { model.orphanSelection.contains($0.url) }
            CleanSummarySheet(title: "Sahipsiz artıklar temizlensin mi?", lines: [
                .init(id: "orphans", title: "Silinmiş uygulamalardan kalanlar", icon: "questionmark.folder", count: sel.count,
                      size: sel.reduce(0) { $0 + $1.size }, insight: Knowledge.group("orphans")),
            ]) {
                Task { await model.cleanOrphans(using: state) }
            }
        }
    }

    // MARK: - Sahipsiz artıklar

    @ViewBuilder
    private var orphansTab: some View {
        if model.loadingOrphans {
            ScanningPlaceholder(text: "Silinmiş uygulamalardan kalan dosyalar aranıyor", icon: "questionmark.folder")
        } else if !model.orphansScanned {
            EmptyStateView(icon: "questionmark.folder", title: "Sahipsiz artıkları bul",
                           message: "Daha önce sildiğin uygulamaların Library'de bıraktığı ayar, önbellek ve destek dosyalarını bulur.",
                           actionTitle: "Taramayı başlat") { Task { await model.scanOrphans() } }
        } else if model.orphans.isEmpty {
            EmptyStateView(icon: "checkmark", title: "Sahipsiz dosya yok", message: "Silinmiş uygulamalardan kalan bir şey bulunamadı.")
        } else {
            ZStack(alignment: .bottom) {
                Card(padding: 10) {
                    AdaptiveScroll {
                        LazyVStack(spacing: 2) {
                            if let i = Knowledge.group("orphans") { InfoBox(insight: i).padding(6) }
                            ForEach(model.orphans) { item in
                                ItemRow(item: item, selected: model.orphanSelection.contains(item.url)) {
                                    if model.orphanSelection.contains(item.url) { model.orphanSelection.remove(item.url) } else { model.orphanSelection.insert(item.url) }
                                }
                            }
                        }
                        .padding(.bottom, 70)
                    }
                }
                .frame(maxHeight: .infinity)
                let total = model.orphans.filter { model.orphanSelection.contains($0.url) }.reduce(0) { $0 + $1.size }
                BottomActionBar(actionTitle: "Gözden geçir ve temizle", actionIcon: "sparkles", enabled: !model.orphanSelection.isEmpty) {
                    HStack(spacing: 10) {
                        BytesText(bytes: total, size: 22)
                        Text("· \(model.orphanSelection.count) öğe").font(.label(12)).foregroundStyle(Theme.inkMuted)
                    }
                } action: { sheet = .orphans }
                .padding(12)
            }
        }
    }
}

struct CategoryTag: View {
    let category: AppCategory
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon).font(.system(size: 9))
            Text(category.title).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8).frame(height: 20)
        .foregroundStyle(category == .essential ? .white : Theme.ink)
        .background(Capsule().fill(category == .unneeded ? Theme.accent : (category == .essential ? Theme.ink : Theme.pillMuted)))
    }
}

private struct AppRow: View {
    let app: AppInfo
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    private var dot: Color {
        switch app.category {
        case .unneeded: Theme.accent
        case .occasional: Theme.line
        case .essential: Theme.success
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 32, height: 32)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(dot).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(selected ? Theme.inkDark : Theme.surface, lineWidth: 2))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.label(12)).lineLimit(1)
                Text([app.genre, app.lastUsed.map { "Son: \(Format.relative($0))" } ?? "Hiç açılmamış"].compactMap { $0 }.joined(separator: " · "))
                    .font(.label(10)).foregroundStyle(selected ? .white.opacity(0.6) : Theme.inkMuted).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(app.size > 0 ? Format.bytes(app.totalSize) : "…").font(.label(11))
                if app.dataSize > 100 * 1024 * 1024 {
                    Text("\(Format.bytes(app.dataSize)) veri").font(.label(9))
                        .foregroundStyle(app.dataSize > app.size * 3 ? (selected ? Theme.accent : Theme.ink) : (selected ? .white.opacity(0.6) : Theme.inkMuted))
                }
            }
        }
        .foregroundStyle(selected ? .white : Theme.ink)
        .padding(.horizontal, 10).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.inkDark : (hover ? Theme.surfaceRaised : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
