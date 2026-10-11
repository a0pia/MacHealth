import AppKit
import Foundation

/// Tam Disk Erişimi durumu ve izin verme yardımcıları.
///
/// macOS, başka uygulamaların `~/Library/Containers` ve `~/Library/Group Containers` klasörlerine her
/// erişimde "… başka uygulamaların verilerine erişmek istiyor" diye ayrı ayrı sorar. Tam Disk Erişimi
/// bunların hepsini tek seferde kapsar; yoksa bu klasörlerin içine hiç girmeyiz ki soru yağmuru olmasın.
enum Permissions {
    private static let lock = NSLock()
    private static var cached: Bool?

    static var hasFullDiskAccess: Bool {
        if Demo.isOn { return true }
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let v = probeFullDiskAccess()
        cached = v
        return v
    }

    /// Durumu yeniden okur (ör. kullanıcı Sistem Ayarları'ndan dönünce).
    @discardableResult
    static func refresh() -> Bool {
        lock.lock(); cached = nil; lock.unlock()
        return hasFullDiskAccess
    }

    /// TCC veritabanı yalnızca Tam Disk Erişimi olan uygulamalarca okunabilir; okumayı denemek soru penceresi açmaz.
    /// Deneme, MacHealth'in Ayarlar'daki Tam Disk Erişimi listesinde (kapalı olarak) görünmesini de sağlar.
    private static func probeFullDiskAccess() -> Bool {
        let paths = ["/Library/Application Support/com.apple.TCC/TCC.db",
                     SafetyGuard.home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path]
        for p in paths {
            let fd = open(p, O_RDONLY)
            if fd >= 0 { close(fd); return true }
        }
        return false
    }

    private static let containerRoots = ["Library/Containers", "Library/Group Containers"]
        .map { SafetyGuard.home.appendingPathComponent($0).path }

    /// Başka bir uygulamanın veri kabı mı (ya da içinde mi)? Tam Disk Erişimi yoksa içine girmek soru penceresi açar.
    static func isAppContainer(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return containerRoots.contains { p.hasPrefix($0 + "/") }
    }

    /// Bu klasörün içinde başka uygulamaların veri kapları var mı? (ör. ~/Library ya da ~/Library/Containers)
    static func containsAppContainers(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return containerRoots.contains { $0 == p || $0.hasPrefix(p + "/") }
    }

    /// Tam Disk Erişimi yokken dokunulmaması gereken yol mu?
    static func shouldAvoid(_ url: URL) -> Bool {
        isAppContainer(url) && !hasFullDiskAccess
    }

    // MARK: - İzin verme

    /// Sistem Ayarları'nda Tam Disk Erişimi listesini açar ve uygulamayı Finder'da seçili gösterir;
    /// listede MacHealth yoksa Finder'dan listeye sürüklemek yeterli.
    @MainActor
    static func requestFullDiskAccess() {
        _ = probeFullDiskAccess()
        SystemActions.openFullDiskAccessSettings()
        if Bundle.main.bundleURL.pathExtension == "app" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                SystemActions.revealInFinder(Bundle.main.bundleURL)
            }
        }
    }

    /// İzin verildikten sonra bazı klasörlerin yeniden okunabilmesi için uygulamayı yeniden açar.
    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Arayüzün izin durumunu izlemesi için: uygulama öne her geldiğinde yeniden kontrol eder.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()
    @Published private(set) var fullDiskAccess = Permissions.hasFullDiskAccess

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PermissionCenter.shared.refresh() }
        }
    }

    func refresh() {
        let v = Permissions.refresh()
        if v != fullDiskAccess { fullDiskAccess = v }
    }
}
