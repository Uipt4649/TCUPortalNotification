//
//  TCUPortalNotificationApp.swift
//  CalenderView
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI

struct CalendarView: View {
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
