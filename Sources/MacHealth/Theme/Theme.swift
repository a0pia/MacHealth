import SwiftUI

/// tema.jpg'den ölçülen renk paleti.
enum Theme {
    static let frame = Color(hex: 0x585856)
    static let canvas = Color(hex: 0xDFDFD7)
    static let surface = Color(hex: 0xEFF0EB)
    static let surfaceRaised = Color.white
    static let pillMuted = Color(hex: 0xE9EAE5)
    static let ink = Color(hex: 0x1F2220)
    static let inkDark = Color(hex: 0x272D2D)
    static let inkMuted = Color(hex: 0x8A8C8B)
    static let line = Color(hex: 0xC9CAC2)
    static let accent = Color(hex: 0xF3FC49)
    static let danger = Color(hex: 0xE5534B)
    static let success = Color(hex: 0x7BC67E)

    static let cardRadius: CGFloat = 26
    static let canvasRadius: CGFloat = 34
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Büyük, ince sayılar (görseldeki "89 bpm" stili).
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .light, design: .default) }
    static func label(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular) }
    static func caption2Muted() -> Font { .system(size: 10, weight: .regular) }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: value)
    }

    /// RAM için ikili birim (8 GB RAM "8 GB" görünsün).
    static func memory(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: value)
    }

    /// "12,4 GB" → ("12,4", "GB")
    static func bytesSplit(_ value: Int64, memory: Bool = false) -> (String, String) {
        let parts = (memory ? Format.memory(value) : bytes(value)).split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? "0", parts.count > 1 ? parts[1] : "")
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "bilinmiyor" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
