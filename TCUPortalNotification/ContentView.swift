//
//  ContentView.swift
//  TCUPortalNotification
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI
import Combine
import UserNotifications
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore
#endif

struct ContentView: View {
    @StateObject private var store = NoticeStore()

    var body: some View {
        TabView {
            NavigationStack {
                InboxView(notices: store.notices, errorMessage: store.errorMessage)
            }
            .tabItem {
                Label("受信箱", systemImage: "tray.full")
            }

            NavigationStack {
                ImportantView(notices: store.notices)
            }
            .tabItem {
                Label("重要", systemImage: "exclamationmark.circle")
            }

            NavigationStack {
                CalendarView(notices: store.notices)
            }
            .tabItem {
                Label("カレンダー", systemImage: "calendar")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
        }
        .onAppear {
            store.startListening()
        }
    }
}

#Preview {
    ContentView()
}

private final class NoticeStore: ObservableObject {
    @Published var notices: [NoticeItem] = []
    @Published var errorMessage: String?

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
    private var listener: ListenerRegistration?
#endif
    private var hasBootstrapped = false
    private var knownIDs: Set<String> = []
    private let knownIDsKey = "known_notice_ids"

    init() {
        if let cached = UserDefaults.standard.array(forKey: knownIDsKey) as? [String] {
            knownIDs = Set(cached)
        }
    }

    func startListening() {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        guard listener == nil else { return }
        LocalNoticeNotifier.shared.requestAuthorization()

        listener = Firestore.firestore()
            .collection("notices")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                let mapped = docs.compactMap(NoticeItem.init(document:))
                let mappedIDs = Set(mapped.map { $0.id })
                let newIDs: Set<String>

                if self.hasBootstrapped {
                    newIDs = mappedIDs.subtracting(self.knownIDs)
                } else {
                    newIDs = []
                    self.hasBootstrapped = true
                }

                self.knownIDs.formUnion(mappedIDs)
                UserDefaults.standard.set(Array(self.knownIDs), forKey: self.knownIDsKey)

                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.notices = mapped
                }

                if !newIDs.isEmpty {
                    let newNotices = mapped.filter { newIDs.contains($0.id) }
                    for notice in newNotices {
                        LocalNoticeNotifier.shared.notifyNewNotice(notice)
                    }
                }
            }
#endif
    }
}

private struct InboxView: View {
    let notices: [NoticeItem]
    let errorMessage: String?

    private var groupedSections: [(String, [NoticeItem])] {
        let grouped = Dictionary(grouping: notices, by: { $0.course })
        let order = ["あなた宛のお知らせ", "大学からのお知らせ", "講義のお知らせ", "ポータル通知"]

        return grouped
            .map { ($0.key.isEmpty ? "ポータル通知" : $0.key, $0.value) }
            .sorted { lhs, rhs in
                let li = order.firstIndex(of: lhs.0) ?? Int.max
                let ri = order.firstIndex(of: rhs.0) ?? Int.max
                if li != ri { return li < ri }
                return lhs.0 < rhs.0
            }
    }

    var body: some View {
        List {
            Section("フィルタ") {
                filterRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            ForEach(groupedSections, id: \.0) { section, items in
                Section(section) {
                    ForEach(items) { notice in
                        NotificationCard(notice: notice)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
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
                FilterChip(title: "未読")
                FilterChip(title: "休講")
                FilterChip(title: "課題")
                FilterChip(title: "教室変更")
            }
            .padding(.vertical, 2)
        }
    }
}

private final class LocalNoticeNotifier {
    static let shared = LocalNoticeNotifier()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyNewNotice(_ notice: NoticeItem) {
        let content = UNMutableNotificationContent()
        content.title = "新着: \(notice.title)"
        content.body = notice.summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "notice-\(notice.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

private struct ImportantView: View {
    let notices: [NoticeItem]

    private var importantNotices: [NoticeItem] {
        notices.filter { $0.isImportant || $0.type == .cancellation || $0.type == .roomChange }
    }

    var body: some View {
        List {
            ForEach(importantNotices) { notice in
                NotificationCard(notice: notice)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("重要")
    }
}

private struct CalendarView: View {
    let notices: [NoticeItem]

    private var grouped: [String: [NoticeItem]] {
        Dictionary(grouping: notices, by: { $0.dateLabel })
    }

    var body: some View {
        List {
            ForEach(grouped.keys.sorted(), id: \.self) { date in
                Section(date) {
                    ForEach(grouped[date] ?? []) { notice in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(notice.type.color)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.title)
                                    .font(.subheadline)
                                Text(notice.type.label + " ・ " + notice.course)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("カレンダー")
    }
}

private struct SettingsView: View {
    @State private var pushEnabled = true
    @State private var classCancelEnabled = true
    @State private var assignmentEnabled = true
    @State private var quietModeEnabled = true

    var body: some View {
        Form {
            Section("通知") {
                Toggle("プッシュ通知", isOn: $pushEnabled)
                Toggle("休講・教室変更", isOn: $classCancelEnabled)
                Toggle("課題通知", isOn: $assignmentEnabled)
            }

            Section("時間帯") {
                Toggle("深夜ミュート (23:00-07:00)", isOn: $quietModeEnabled)
            }
        }
        .navigationTitle("設定")
    }
}

private struct NotificationCard: View {
    let notice: NoticeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TypeTag(type: notice.type)
                Text(notice.course)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if notice.isUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }

            Text(notice.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(notice.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(notice.dateLabel, systemImage: "clock")
                if let dueDate = notice.dueDateLabel {
                    Label("締切 \(dueDate)", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.isUnread ? notice.type.color.opacity(0.08) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(notice.type.color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct TypeTag: View {
    let type: NoticeType

    var body: some View {
        Text(type.label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(type.color)
            .clipShape(Capsule())
    }
}

private struct FilterChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

private enum NoticeType {
    case cancellation
    case makeupClass
    case roomChange
    case assignment
    case general

    var label: String {
        switch self {
        case .cancellation:
            return "休講"
        case .makeupClass:
            return "補講"
        case .roomChange:
            return "教室変更"
        case .assignment:
            return "課題"
        case .general:
            return "お知らせ"
        }
    }

    var color: Color {
        switch self {
        case .cancellation:
            return Color(red: 0.85, green: 0.17, blue: 0.13)
        case .makeupClass:
            return Color(red: 0.97, green: 0.56, blue: 0.03)
        case .roomChange:
            return Color(red: 0.09, green: 0.36, blue: 0.83)
        case .assignment:
            return Color(red: 0.48, green: 0.35, blue: 0.97)
        case .general:
            return Color(red: 0.4, green: 0.44, blue: 0.52)
        }
    }
}

private struct NoticeItem: Identifiable {
    let id: String
    let type: NoticeType
    let course: String
    let title: String
    let summary: String
    let dateLabel: String
    let dueDateLabel: String?
    let isUnread: Bool
    let isImportant: Bool

    init(
        id: String = UUID().uuidString,
        type: NoticeType,
        course: String,
        title: String,
        summary: String,
        dateLabel: String,
        dueDateLabel: String?,
        isUnread: Bool,
        isImportant: Bool
    ) {
        self.id = id
        self.type = type
        self.course = course
        self.title = title
        self.summary = summary
        self.dateLabel = dateLabel
        self.dueDateLabel = dueDateLabel
        self.isUnread = isUnread
        self.isImportant = isImportant
    }

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let title = data["title"] as? String, !title.isEmpty else {
            return nil
        }

        let typeRaw = (data["type"] as? String) ?? "general"
        let body = (data["body"] as? String) ?? ""
        let publishedAtRaw = (data["publishedAtRaw"] as? String) ?? ""
        let section = (data["section"] as? String) ?? "ポータル通知"

        self.id = document.documentID
        self.type = NoticeType.fromFirestore(typeRaw)
        self.course = section.isEmpty ? "ポータル通知" : section
        self.title = title
        self.summary = body.isEmpty ? "本文なし" : body
        self.dateLabel = publishedAtRaw.isEmpty ? "日時不明" : publishedAtRaw
        self.dueDateLabel = nil
        self.isUnread = true
        self.isImportant = self.type == .cancellation || self.type == .roomChange || self.type == .assignment
    }
#endif

    static let sampleData: [NoticeItem] = [
        NoticeItem(
            type: .cancellation,
            course: "情報基礎A",
            title: "本日4限 休講のお知らせ",
            summary: "担当教員の都合により、4/4(土)の4限は休講です。",
            dateLabel: "4/4 09:10",
            dueDateLabel: nil,
            isUnread: true,
            isImportant: true
        ),
        NoticeItem(
            type: .assignment,
            course: "データ構造",
            title: "第2回レポート提出について",
            summary: "提出先とフォーマットを更新しました。必ず最新版を確認してください。",
            dateLabel: "4/3 18:40",
            dueDateLabel: "4/8 23:59",
            isUnread: true,
            isImportant: true
        ),
        NoticeItem(
            type: .roomChange,
            course: "英語II",
            title: "次回授業の教室変更",
            summary: "4/7(火)の授業は3号館301教室へ変更されます。",
            dateLabel: "4/3 11:20",
            dueDateLabel: nil,
            isUnread: false,
            isImportant: true
        ),
        NoticeItem(
            type: .general,
            course: "大学からのお知らせ",
            title: "健康診断日程のお知らせ",
            summary: "2026年度の学生定期健康診断の日程が公開されました。",
            dateLabel: "4/1 10:00",
            dueDateLabel: nil,
            isUnread: false,
            isImportant: false
        ),
        NoticeItem(
            type: .makeupClass,
            course: "線形代数",
            title: "補講の実施について",
            summary: "先週休講分の補講を4/10(金)5限に実施します。",
            dateLabel: "3/31 17:50",
            dueDateLabel: nil,
            isUnread: true,
            isImportant: false
        )
    ]
}

private extension NoticeType {
    static func fromFirestore(_ value: String) -> NoticeType {
        switch value {
        case "cancellation":
            return .cancellation
        case "makeupClass":
            return .makeupClass
        case "roomChange":
            return .roomChange
        case "assignment":
            return .assignment
        default:
            return .general
        }
    }
}
