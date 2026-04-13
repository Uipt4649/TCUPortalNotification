//
//  TCUPortalNotificationApp.swift
//  ImportantView
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI

struct ImportantView: View {
    let notices: [NoticeItem]

    private var importantNotices: [NoticeItem] {
        notices
            .filter { $0.isImportant || $0.type == .cancellation || $0.type == .roomChange }
            .sorted { $0.receivedAtEpoch > $1.receivedAtEpoch }
    }

    var body: some View {
        List {
            Section("判定ルール") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("このタブは手動追加ではなく自動判定です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("対象: 休講 / 教室変更 / 課題")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.vertical, 2)
            }

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
