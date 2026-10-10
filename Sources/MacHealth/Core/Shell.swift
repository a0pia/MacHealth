import AppKit
import Foundation

enum Shell {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String] = []) -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Output(status: p.terminationStatus,
                      stdout: String(decoding: o, as: UTF8.self),
                      stderr: String(decoding: e, as: UTF8.self))
    }

    /// Yönetici şifresi isteyerek komut çalıştırır (macOS'un kendi şifre penceresiyle).
    @discardableResult
    static func runAsAdmin(_ command: String) -> Output {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }
}

enum SystemActions {
    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    static func openAccessibilityDisplaySettings() {
        open("x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
