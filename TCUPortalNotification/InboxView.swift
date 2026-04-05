import SwiftUI

struct InboxView: View {
    let notices: [NoticeItem]
    let errorMessage: String?
    let portalStatus: PortalStatus?
    @State private var selectedSections: Set<String> = Set(PortalSectionStyle.all.map(\.name))

    private var groupedSections: [(String, [NoticeItem])] {
        let filtered = notices.filter { selectedSections.contains(PortalSectionStyle.normalized($0.course)) }
        let grouped = Dictionary(grouping: filtered, by: { PortalSectionStyle.normalized($0.course) })
        let order = PortalSectionStyle.all.map(\.name)

        return grouped.sorted {
            let li = order.firstIndex(of: $0.key) ?? Int.max
            let ri = order.firstIndex(of: $1.key) ?? Int.max
            if li != ri { return li < ri }
            return $0.key < $1.key
        }
    }

    var body: some View {
        List {
            if let portalStatus, portalStatus.authRequired {
                Section("同期状態") {
                    SessionExpiredBanner(status: portalStatus)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                }
            }

            Section("フィルタ") {
                filterRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            ForEach(groupedSections, id: \.0) { section, items in
                Section {
                    ForEach(items) { notice in
                        NotificationCard(notice: notice)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PortalSectionStyle.color(for: section))
                            .frame(width: 8, height: 8)
                        Text(section)
                    }
                }
            }

            if notices.isEmpty {
                Section("状態") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Firestoreから取得中、またはデータがありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let errorMessage {
                            Text("エラー: \(errorMessage)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("受信箱")
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PortalSectionStyle.all, id: \.name) { section in
                    FilterChip(
                        title: section.name,
                        color: section.color,
                        isSelected: selectedSections.contains(section.name)
                    ) {
                        if selectedSections.contains(section.name) {
                            selectedSections.remove(section.name)
                            if selectedSections.isEmpty {
                                selectedSections = Set(PortalSectionStyle.all.map(\.name))
                            }
                        } else {
                            selectedSections.insert(section.name)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct SessionExpiredBanner: View {
    let status: PortalStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ポータル再認証が必要です", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("通知取得が停止中です。ターミナルで次を実行してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("python src/run_once.py --init-session")
                .font(.caption.monospaced())
            Text("python src/run_once.py")
                .font(.caption.monospaced())
            if let checkedAt = status.checkedAtLabel {
                Text("最終確認: \(checkedAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}
