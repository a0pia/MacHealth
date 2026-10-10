import AppKit
import SwiftUI

@main
struct MacHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @AppStorage(Settings.showMenuBarKey) private var showMenuBar = true

    init() { Settings.registerDefaults() }

    var body: some Scene {
        Window("MacHealth", id: "main") {
            MainWindow()
                .environmentObject(state)
                .environmentObject(HistoryStore.shared)
                .frame(minWidth: 1200, minHeight: 760)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar…") { state.go(.settings) }.keyboardShortcut(",")
            }
            CommandMenu("Git") {
                ForEach(Array(Module.shortcutOrder.enumerated()), id: \.offset) { i, m in
                    Button(m.title) { state.go(m) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button("Geri") { state.back() }.keyboardShortcut("[", modifiers: .command)
                Button("Geçmiş") { state.go(.history) }.keyboardShortcut("y", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel()
                .environmentObject(state)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if IconRenderer.runIfRequested() { NSApp.terminate(nil); return }
        // Tema açık renkli tasarlandı: sistem koyu moddayken menü paneli, açılır pencereler ve
        // sayfalar beyaz yazı + açık zemin ile okunamaz hale geliyordu. Tüm uygulamayı açık görünüme sabitle.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Snapshot.runIfRequested()
        DiskWatcher.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Settings.showMenuBarKey)
    }
}
