import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var history: HistoryStore
    @State private var pendingRestore: CleanupRecord?
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 28) {
                StatBlock(label: "Toplam açılan alan", value: Format.bytesSplit(history.totalFreed).0, unit: Format.bytesSplit(history.totalFreed).1, size: 30)
                StatBlock(label: "Temizlik", value: "\(history.records.count)", size: 30)
                Spacer()
                PillButton(title: "Log dosyası", icon: "doc.text", style: .raised, compact: true) { SystemActions.revealInFinder(ActivityLog.url) }
                PillButton(title: "Geçmişi temizle", icon: "xmark", style: .muted, compact: true) { confirmClear = true }
                    .disabled(history.records.isEmpty)
            }

            if history.records.isEmpty {
                Card {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "Henüz temizlik yok",
                                   message: "Yaptığın her temizlik burada listelenir. Çöp Kutusu boşaltılmadığı sürece tek tuşla geri alabilirsin.")
                }
                .frame(maxHeight: .infinity)
            } else {
                chart
                Card(padding: 10) {
                    AdaptiveScroll {
                        VStack(spacing: 2) {
                            ForEach(history.records) { r in RecordRow(record: r) { pendingRestore = r } }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .confirmationDialog("Geri alınsın mı?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            if let r = pendingRestore {
                Button("\(r.files.count) öğeyi geri yükle") {
                    let res = history.restore(r)
                    state.showToast("\(res.restored) öğe geri yüklendi" + (res.failed > 0 ? " · \(res.failed) öğe bulunamadı" : ""))
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Çöp Kutusu'na taşınan dosyalar eski yerlerine geri konacak. Kalıcı silinenler (Çöp Kutusu boşaltma) geri gelmez.")
        }
        .confirmationDialog("Geçmiş temizlensin mi?", isPresented: $confirmClear) {
            Button("Temizle", role: .destructive) { history.clear() }
        } message: {
            Text("Sadece kayıtlar silinir; dosyalar etkilenmez. Geri alma imkânı kaybolur.")
        }
    }

    private var chart: some View {
        let recent = Array(history.records.prefix(24).reversed())
        let maxV = max(recent.map(\.totalSize).max() ?? 1, 1)
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Son temizlikler").font(.label(11)).foregroundStyle(Theme.inkMuted)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(recent) { r in
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(r.restored ? Theme.line : Theme.accent)
                                .frame(width: 16, height: max(8, 90 * CGFloat(Double(r.totalSize) / Double(maxV))))
                                .help("\(r.module) · \(Format.bytes(r.totalSize))")
                            Text(r.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))))
                                .font(.system(size: 8)).foregroundStyle(Theme.inkMuted).fixedSize()
                        }
                    }
                    Spacer()
                }
                .frame(height: 110, alignment: .bottom)
            }
        }
    }
}

private struct RecordRow: View {
    let record: CleanupRecord
    let restore: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AccentBadge(icon: icon, size: 32, dimmed: record.restored)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.module).font(.label(13))
                    Text("\(record.date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "tr_TR")))) · \(record.files.count) öğe")
                        .font(.label(10)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if record.restored {
                    Text("Geri alındı").font(.label(11)).foregroundStyle(Theme.inkMuted)
                }
                BytesText(bytes: record.totalSize, size: 18).opacity(record.restored ? 0.4 : 1)
                if record.canRestore {
                    PillButton(title: "Geri al", icon: "arrow.uturn.backward", style: .raised, compact: true, action: restore)
                }
                Image(systemName: "chevron.down").font(.system(size: 10))
                    .rotationEffect(.degrees(expanded ? 180 : 0)).frame(width: 24)
            }
            .padding(.horizontal, 12).frame(height: 56)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.files.prefix(100), id: \.self) { f in
                        HStack {
                            Text(f.original.replacingOccurrences(of: SafetyGuard.home.path, with: "~"))
                                .font(.label(10)).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if f.trashed == nil { Text("kalıcı silindi").font(.label(9)).foregroundStyle(Theme.danger) }
                            Text(Format.bytes(f.size)).font(.label(10))
                        }
                    }
                    if record.files.count > 100 { Text("+\(record.files.count - 100) öğe").font(.label(10)).foregroundStyle(Theme.inkMuted) }
                }
                .padding(.horizontal, 58).padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(expanded ? Theme.surfaceRaised : .clear))
    }

    private var icon: String {
        Module.allCases.first { $0.title == record.module }?.icon ?? "sparkles"
    }
}
