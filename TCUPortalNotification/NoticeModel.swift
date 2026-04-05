import SwiftUI
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum NoticeType {
    case cancellation
    case makeupClass
    case roomChange
    case assignment
    case general

    var label: String {
        switch self {
        case .cancellation: return "休講"
        case .makeupClass: return "補講"
        case .roomChange: return "教室変更"
        case .assignment: return "課題"
        case .general: return "お知らせ"
        }
    }

    var color: Color {
        switch self {
        case .cancellation: return Color(red: 0.85, green: 0.17, blue: 0.13)
        case .makeupClass: return Color(red: 0.97, green: 0.56, blue: 0.03)
        case .roomChange: return Color(red: 0.09, green: 0.36, blue: 0.83)
        case .assignment: return Color(red: 0.48, green: 0.35, blue: 0.97)
        case .general: return Color(red: 0.4, green: 0.44, blue: 0.52)
        }
    }

    static func fromFirestore(_ value: String) -> NoticeType {
        switch value {
        case "cancellation": return .cancellation
        case "makeupClass": return .makeupClass
        case "roomChange": return .roomChange
        case "assignment": return .assignment
        default: return .general
        }
    }
}

struct NoticeItem: Identifiable {
    let id: String
    let type: NoticeType
    let course: String
    let title: String
    let summary: String
    let dateLabel: String
    let dueDateLabel: String?
    let sourceURL: URL?
    let sender: String
    let readAtLabel: String
    let receivedAtEpoch: Int
    let isUnread: Bool
    let isImportant: Bool
    var portalURL: URL {
        sourceURL ?? URL(string: "https://websrv.tcu.ac.jp/tcu_web_v3/wbasoapr.do?contenam=wbasoapr&buttonName=showAll")!
    }

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let title = data["title"] as? String, !title.isEmpty else { return nil }

        let typeRaw = (data["type"] as? String) ?? "general"
        let body = (data["body"] as? String) ?? ""
        let receivedAtRaw = (data["receivedAtRaw"] as? String) ?? (data["publishedAtRaw"] as? String) ?? ""
        let readAtRaw = (data["readAtRaw"] as? String) ?? ""
        let sender = (data["sender"] as? String) ?? ""
        let section = PortalSectionStyle.normalized((data["section"] as? String) ?? "")
        guard !section.isEmpty else { return nil }
        let sourceUrlRaw = (data["sourceUrl"] as? String) ?? ""

        self.id = document.documentID
        self.type = NoticeType.fromFirestore(typeRaw)
        self.course = section
        self.title = title
        self.summary = body.isEmpty ? "本文なし" : body
        self.dateLabel = receivedAtRaw.isEmpty ? "日時不明" : receivedAtRaw
        self.dueDateLabel = nil
        self.sourceURL = URL(string: sourceUrlRaw)
        self.sender = sender
        self.readAtLabel = readAtRaw
        self.receivedAtEpoch = (data["receivedAtEpoch"] as? Int) ?? 0
        self.isUnread = readAtRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.isImportant = self.type == .cancellation || self.type == .roomChange || self.type == .assignment
    }
#endif
}

struct PortalSectionStyle {
    let name: String
    let color: Color

    static let all: [PortalSectionStyle] = [
        .init(name: "大学からのお知らせ", color: Color(red: 0.72, green: 0.64, blue: 0.90)),
        .init(name: "あなた宛のお知らせ", color: Color(red: 0.93, green: 0.44, blue: 0.62)),
        .init(name: "教員からのお知らせ", color: Color(red: 0.66, green: 0.80, blue: 0.36)),
        .init(name: "誰でも投稿", color: Color(red: 0.84, green: 0.66, blue: 0.12)),
        .init(name: "講義のお知らせ", color: Color(red: 0.14, green: 0.52, blue: 0.31)),
        .init(name: "伝言", color: Color(red: 0.36, green: 0.64, blue: 0.82)),
    ]

    static func normalized(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("大学からのお知らせ") { return "大学からのお知らせ" }
        if value.contains("あなた宛のお知らせ") { return "あなた宛のお知らせ" }
        if value.contains("教員からのお知らせ") { return "教員からのお知らせ" }
        if value.contains("誰でも投稿") { return "誰でも投稿" }
        if value.contains("講義のお知らせ") { return "講義のお知らせ" }
        if value.contains("伝言") { return "伝言" }
        return ""
    }

    static func color(for name: String) -> Color {
        all.first(where: { $0.name == normalized(name) })?.color ?? Color.gray
    }
}

struct PortalStatus {
    let authRequired: Bool
    let reason: String
    let checkedAtLabel: String?

    init(data: [String: Any]) {
        authRequired = (data["authRequired"] as? Bool) ?? false
        reason = (data["reason"] as? String) ?? ""
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        if let ts = data["checkedAt"] as? Timestamp {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M/d HH:mm"
            checkedAtLabel = formatter.string(from: ts.dateValue())
        } else {
            checkedAtLabel = nil
        }
#else
        checkedAtLabel = nil
#endif
    }
}
