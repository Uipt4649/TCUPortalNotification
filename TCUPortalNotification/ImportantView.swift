import SwiftUI

struct ImportantView: View {
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
