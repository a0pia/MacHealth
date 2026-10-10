import SwiftUI

extension Insight.Risk {
    var color: Color {
        switch self {
        case .safe: Theme.success
        case .low: Theme.accent
        case .caution: Theme.danger
        }
    }

    var icon: String {
        switch self {
        case .safe: "checkmark.shield"
        case .low: "exclamationmark.shield"
        case .caution: "exclamationmark.triangle"
        }
    }
}

struct RiskBadge: View {
    let risk: Insight.Risk
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: risk.icon).font(.system(size: 9, weight: .semibold))
            Text(risk.title).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8).frame(height: 20)
        .foregroundStyle(risk == .caution ? .white : Theme.ink)
        .background(Capsule().fill(risk == .safe ? Theme.success.opacity(0.45) : risk.color))
    }
}

/// "Silersen ne olur?" kutusu.
struct InfoBox: View {
    let insight: Insight
    var title = "Silersen ne olur?"
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(insight.risk == .safe ? Theme.success.opacity(0.35) : insight.risk.color)
                Image(systemName: "info").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(insight.risk == .caution ? .white : Theme.ink)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                    RiskBadge(risk: insight.risk)
                }
                if !compact {
                    Text(insight.what).font(.label(11)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(insight.consequences, id: \.self) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(Theme.ink.opacity(0.5)).frame(width: 4, height: 4).offset(y: -2)
                            Text(.init(c)).font(.label(11)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(alignment: .leading) {
                    Capsule().fill(insight.risk == .safe ? Theme.success : insight.risk.color)
                        .frame(width: 4).padding(.vertical, 14).padding(.leading, 3)
                }
        )
    }
}

/// Tıklayınca bilgi kutusunu açan küçük "i" butonu.
struct InfoButton: View {
    let insight: Insight
    var size: CGFloat = 26
    @State private var show = false
    @State private var hover = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "info")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(hover ? Theme.ink : Theme.inkMuted)
                .frame(width: size, height: size)
                .background(Circle().fill(hover ? Theme.accent : Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Silersen ne olur?")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            InfoBox(insight: insight).frame(width: 340).padding(6).background(Theme.surface)
        }
    }
}

// MARK: - Temizlik özeti sayfası

/// Silmeden önce gösterilen özet: hangi gruplardan ne silinecek ve sonuçları.
struct CleanSummarySheet: View {
    struct Line: Identifiable {
        let id: String
        let title: String
        let icon: String
        let count: Int
        let size: Int64
        let insight: Insight?
    }

    let title: String
    let lines: [Line]
    var actionTitle = "Çöp'e taşı"
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: String?

    private var total: Int64 { lines.reduce(0) { $0 + $1.size } }
    private var worst: Insight.Risk { lines.compactMap { $0.insight?.risk }.max() ?? .safe }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.display(24))
                    HStack(spacing: 8) {
                        BytesText(bytes: total, size: 20)
                        Text("· \(lines.reduce(0) { $0 + $1.count }) öğe").font(.label(12)).foregroundStyle(Theme.inkMuted)
                        RiskBadge(risk: worst)
                    }
                }
                Spacer()
                CircleIconButton(icon: "xmark", size: 32) { dismiss() }
            }

            Text("Silmeden önce ne olacağına bir göz at. Her satıra tıklayarak ayrıntıyı görebilirsin.")
                .font(.label(12)).foregroundStyle(Theme.inkMuted)

            AdaptiveScroll {
                VStack(spacing: 8) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentBadge(icon: line.icon, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.title).font(.label(13))
                                    if let first = line.insight?.consequences.first {
                                        Text(.init(first)).font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if let r = line.insight?.risk { RiskBadge(risk: r) }
                                Text(Format.bytes(line.size)).font(.label(12)).frame(width: 76, alignment: .trailing)
                                Image(systemName: "chevron.down").font(.system(size: 10))
                                    .rotationEffect(.degrees(expanded == line.id ? 180 : 0))
                            }
                            if expanded == line.id, let i = line.insight {
                                InfoBox(insight: i, compact: false)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(duration: 0.3)) { expanded = expanded == line.id ? nil : line.id } }
                    }
                }
            }
            .frame(maxHeight: 380)

            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Theme.inkMuted)
                Text(lines.contains { $0.id == "trash" }
                     ? "Çöp Kutusu'ndakiler kalıcı silinir. Diğer her şey Geçmiş ekranından geri alınabilir."
                     : "Her şey Çöp Kutusu'na taşınır ve Geçmiş ekranından geri alınabilir.")
                    .font(.label(11)).foregroundStyle(Theme.inkMuted)
                Spacer()
                PillButton(title: "Vazgeç", style: .muted) { dismiss() }
                Button {
                    dismiss()
                    onConfirm()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text(actionTitle).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 22).frame(height: 40)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(Theme.canvas)
    }
}

extension CleanSummarySheet.Line {
    /// ScanModel'deki seçili öğelerden özet satırları üretir.
    @MainActor
    static func from(_ model: ScanModel) -> [CleanSummarySheet.Line] {
        let selected = Set(model.selectedItems.map(\.url))
        var lines: [CleanSummarySheet.Line] = []
        var index: [String: Int] = [:]
        // Aynı bilgi anahtarlı gruplar (ör. yüzlerce kopya grubu) tek satırda birleşir.
        for g in model.result.groups {
            let sel = g.items.filter { selected.contains($0.url) }
            guard !sel.isEmpty else { continue }
            let key = g.insightKey ?? g.id
            let size = sel.reduce(0) { $0 + $1.size }
            if let i = index[key] {
                let old = lines[i]
                lines[i] = .init(id: key, title: old.title, icon: old.icon, count: old.count + sel.count,
                                 size: old.size + size, insight: old.insight)
            } else {
                index[key] = lines.count
                let title = g.insightKey == "duplicates" ? "Kopya dosyalar" : g.title
                lines.append(.init(id: key, title: title, icon: g.insightKey == "duplicates" ? "doc.on.doc" : g.icon,
                                   count: sel.count, size: size, insight: g.insight))
            }
        }
        return lines
    }
}
