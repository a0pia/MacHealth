import AppKit
import QuickLookUI
import SwiftUI

/// Gruplara ayrılmış, seçilebilir temizlik listesi (Sistem Çöpü, Büyük Dosyalar).
struct GroupedCleanList: View {
    @ObservedObject var model: ScanModel
    var showDates = true
    /// false ise her grupta "i" butonu yerine listenin başında tek bir bilgi kutusu gösterilir.
    var groupInfo = true

    var body: some View {
        AdaptiveScroll {
            LazyVStack(spacing: 10) {
                if !groupInfo, let insight = model.result.groups.first?.insight {
                    InfoBox(insight: insight)
                }
                ForEach(Array(model.result.groups.enumerated()), id: \.element.id) { i, group in
                    GroupCard(model: model, group: group, showDates: showDates, showInfo: groupInfo)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity.combined(with: .scale(scale: 0.96))))
                }
            }
            .padding(.bottom, 90)
        }
        .scrollIndicators(.never)
    }
}

private struct GroupCard: View {
    @ObservedObject var model: ScanModel
    let group: CleanGroup
    let showDates: Bool
    var showInfo = true

    private var isExpanded: Bool { model.expanded.contains(group.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { model.toggle(group: group) } label: { SelectBox(state: model.state(of: group)) }
                    .buttonStyle(.plain)
                AccentBadge(icon: group.icon, size: 38, dimmed: model.state(of: group) == .none)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(group.title).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        Text("\(group.items.count) öğe").font(.label(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Text(group.note).font(.label(11)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer()
                if let insight = group.insight, showInfo {
                    RiskBadge(risk: insight.risk)
                    InfoButton(insight: insight)
                }
                BytesText(bytes: group.totalSize, size: 20)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    if isExpanded { model.expanded.remove(group.id) } else { model.expanded.insert(group.id) }
                }
            }

            if isExpanded {
                VStack(spacing: 2) {
                    if showInfo, let insight = group.insight {
                        InfoBox(insight: insight)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                    ForEach(group.items.prefix(300)) { item in
                        ItemRow(item: item, selected: model.selection.contains(item.url), showDate: showDates) {
                            model.toggle(item)
                        }
                    }
                    if group.items.count > 300 {
                        Text("+\(group.items.count - 300) öğe daha").font(.label(11)).foregroundStyle(Theme.inkMuted).padding(8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
        .transition(.opacity)
    }
}

struct ItemRow: View {
    let item: CleanItem
    let selected: Bool
    var showDate = true
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) { SelectBox(state: selected ? .all : .none) }.buttonStyle(.plain)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(.label(12)).foregroundStyle(Theme.ink).lineLimit(1)
                    if let caution = item.caution {
                        Text(caution)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 7).frame(height: 16)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Text(item.detail ?? item.url.path.replacingOccurrences(of: SafetyGuard.home.path, with: "~"))
                    .font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if showDate {
                Text(Format.date(item.modified)).font(.label(11)).foregroundStyle(Theme.inkMuted).frame(width: 90, alignment: .trailing)
            }
            Text(Format.bytes(item.size)).font(.label(12)).foregroundStyle(Theme.ink).frame(width: 80, alignment: .trailing)
            if let insight = Knowledge.item(item) {
                InfoButton(insight: insight, size: 22)
            }
            if hover {
                HStack(spacing: 4) {
                    MiniIcon(icon: "eye", help: "Önizle") { QuickLook.show(item.url) }
                    MiniIcon(icon: "folder", help: "Finder'da göster") { SystemActions.revealInFinder(item.url) }
                }
            } else {
                Color.clear.frame(width: 56, height: 1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Theme.surfaceRaised : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
    }
}

struct MiniIcon: View {
    let icon: String
    var help = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.pillMuted))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Quick Look önizleme paneli.
@MainActor
enum QuickLook {
    private static let source = PreviewSource()

    static func show(_ url: URL) {
        source.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = source
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    private final class PreviewSource: NSObject, QLPreviewPanelDataSource {
        var url: URL?
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
    }
}
