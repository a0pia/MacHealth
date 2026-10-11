import Foundation

/// Boş klasörler ve yeniden üretilebilir geliştirici klasörleri (node_modules, .venv, Pods…).
enum FoldersScanner {
    private static let home = SafetyGuard.home

    /// Klasör adı → (aracın adı, kardeş dosya şartı, yeniden kurma komutu)
    private static let devRules: [String: (tool: String, siblings: [String], restore: String)] = [
        "node_modules": ("Node.js", ["package.json"], "npm install"),
        ".venv": ("Python", [], "pip install -r requirements.txt"),
        "venv": ("Python", [], "pip install -r requirements.txt"),
        "Pods": ("CocoaPods", ["Podfile"], "pod install"),
        "target": ("Rust", ["Cargo.toml"], "cargo build"),
        ".gradle": ("Gradle", ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"], "./gradlew build"),
        "build": ("Gradle / Flutter", ["build.gradle", "build.gradle.kts", "pubspec.yaml"], "yeniden derle"),
        ".next": ("Next.js", ["package.json"], "npm run build"),
        ".nuxt": ("Nuxt", ["package.json"], "npm run build"),
        ".dart_tool": ("Flutter", ["pubspec.yaml"], "flutter pub get"),
        ".expo": ("Expo", ["package.json"], "npx expo start"),
        "__pycache__": ("Python", [], "otomatik oluşur"),
        ".pytest_cache": ("pytest", [], "otomatik oluşur"),
        ".turbo": ("Turborepo", ["package.json"], "otomatik oluşur"),
        ".parcel-cache": ("Parcel", ["package.json"], "otomatik oluşur"),
    ]

    /// Bu dosyalardan birini içeren klasör bir projedir; içindeki boş klasörlere dokunulmaz.
    private static let projectMarkers: Set<String> = [
        "package.json", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pubspec.yaml",
        "Cargo.toml", "Podfile", "pom.xml", "go.mod", "pyproject.toml", "requirements.txt", "CMakeLists.txt",
        "Makefile", "Package.swift", "composer.json", "Gemfile",
    ]

    private static let ignoredEntries: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    static func scan() -> ScanResult {
        if Demo.isOn { return Demo.folders }
        let tops = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0 != "Library" && !$0.hasPrefix(".") }
            .map { home.appendingPathComponent($0) }

        var dev: [CleanItem] = []
        var emptyCandidates: [URL] = []
        let lock = NSLock()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]

        DispatchQueue.concurrentPerform(iterations: tops.count) { i in
            guard let e = FileManager.default.enumerator(at: tops[i], includingPropertiesForKeys: keys, options: [],
                                                         errorHandler: { _, _ in true }) else { return }
            var localDev: [CleanItem] = []
            var childCount: [String: Int] = [:]
            var dirs: [URL] = []
            var skipped = Set<String>()
            var repoRoots: [String] = []

            for case let url as URL in e {
                let name = url.lastPathComponent
                let parent = url.deletingLastPathComponent().path
                if !ignoredEntries.contains(name) { childCount[parent, default: 0] += 1 }
                if projectMarkers.contains(name) { repoRoots.append(parent + "/") }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true else { continue }

                if name == ".git" { repoRoots.append(parent + "/"); skipped.insert(url.path); e.skipDescendants(); continue }
                if v.isPackage == true || name.hasSuffix(".localized") { skipped.insert(url.path); e.skipDescendants(); continue }

                if let rule = devRules[name], let item = devItem(url, rule: rule) {
                    localDev.append(item)
                    skipped.insert(url.path)
                    e.skipDescendants()
                    continue
                }
                // Gizli klasörlerin içine boş klasör aramak için girme
                if name.hasPrefix(".") { skipped.insert(url.path); e.skipDescendants(); continue }
                dirs.append(url)
            }

            // Git depoları ve projeler içindeki boş klasörler projenin parçası olabilir (ör. Android "libs"), dokunma.
            let empties = dirs.filter { d in
                childCount[d.path, default: 0] == 0 && !skipped.contains(d.path) && !repoRoots.contains { d.path.hasPrefix($0) }
            }
            lock.lock(); dev += localDev; emptyCandidates += empties; lock.unlock()
        }

        // Boş klasörleri tekrar doğrula
        let empty = emptyCandidates.compactMap { u -> CleanItem? in
            guard SafetyGuard.isDeletable(u),
                  let entries = try? FileManager.default.contentsOfDirectory(atPath: u.path),
                  entries.allSatisfy({ ignoredEntries.contains($0) }) else { return nil }
            return CleanItem(url: u, size: FileSizer.size(of: u), modified: FileSizer.modified(u),
                             detail: LargeFilesScanner.shortPath(u.deletingLastPathComponent()))
        }
        .sorted { $0.url.path < $1.url.path }

        return ScanResult(groups: [
            CleanGroup(id: "devFolders", title: "Geliştirici klasörleri", icon: "shippingbox",
                       note: "Projelerdeki node_modules, .venv, Pods gibi yeniden kurulabilen klasörler. Aktif projeler seçilmez.",
                       items: dev.sorted { $0.size > $1.size }),
            CleanGroup(id: "emptyFolders", title: "Boş klasörler", icon: "folder",
                       note: "İçinde hiçbir dosya olmayan klasörler.", items: empty),
        ].filter { !$0.items.isEmpty }, deniedPaths: [])
    }

    private static func devItem(_ url: URL, rule: (tool: String, siblings: [String], restore: String)) -> CleanItem? {
        let project = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !rule.siblings.isEmpty, !rule.siblings.contains(where: { fm.fileExists(atPath: project.appendingPathComponent($0).path) }) {
            return nil
        }
        if url.lastPathComponent == ".venv" || url.lastPathComponent == "venv" {
            guard fm.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) else { return nil }
        }
        let size = FileSizer.size(of: url)
        guard size > 1024 * 1024 else { return nil }
        let lastTouched = projectActivity(project)
        let active = (lastTouched ?? .distantPast) > Date().addingTimeInterval(-14 * 24 * 3600)
        return CleanItem(url: url, name: "\(project.lastPathComponent) · \(url.lastPathComponent)", size: size, modified: lastTouched,
                         detail: "\(rule.tool) · geri getirmek için: \(rule.restore) · \(LargeFilesScanner.shortPath(project))",
                         caution: active ? "Aktif proje" : nil)
    }

    /// Projenin üst seviyesindeki dosyaların en son değişme tarihi.
    private static func projectActivity(_ project: URL) -> Date? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: project.path)) ?? []
        return names.filter { !devRules.keys.contains($0) }
            .compactMap { FileSizer.modified(project.appendingPathComponent($0)) }
            .max()
    }
}
