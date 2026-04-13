//
//  TCUPortalNotificationApp.swift
//  InboxView
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI
import UIKit
import SafariServices

struct InboxView: View {
    let notices: [NoticeItem]
    let errorMessage: String?
    let portalStatus: PortalStatus?
    let lastAppRefreshAt: Date?
    let onRefreshStatus: () -> Void
    @State private var selectedSection: String = PortalSectionStyle.all.first?.name ?? "大学からのお知らせ"
    @State private var searchText: String = ""

    private func sectionKey(for notice: NoticeItem) -> String {
        let normalized = PortalSectionStyle.normalized(notice.course)
        if !normalized.isEmpty {
            return normalized
        }
        let raw = notice.course.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "その他" : raw
    }

    private func filteredNotices(for section: String) -> [NoticeItem] {
        notices
            .filter { sectionKey(for: $0) == section }
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.receivedAtEpoch > $1.receivedAtEpoch }
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            ForEach(PortalSectionStyle.all, id: \.name) { section in
                InboxSectionPage(
                    section: section.name,
                    sectionColor: section.color,
                    notices: filteredNotices(for: section.name),
                    errorMessage: errorMessage,
                    isGlobalEmpty: notices.isEmpty,
                    portalStatus: portalStatus,
                    lastAppRefreshAt: lastAppRefreshAt,
                    onRefreshStatus: onRefreshStatus,
                    selectedSection: $selectedSection
                )
                .tag(section.name)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.systemGroupedBackground))
        .navigationTitle("受信箱")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "タイトルを検索")
    }
}

struct InboxSectionPage: View {
    let section: String
    let sectionColor: Color
    let notices: [NoticeItem]
    let errorMessage: String?
    let isGlobalEmpty: Bool
    let portalStatus: PortalStatus?
    let lastAppRefreshAt: Date?
    let onRefreshStatus: () -> Void
    @Binding var selectedSection: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("同期状態")
                    .font(.headline)

                SyncStatusCard(status: portalStatus, lastAppRefreshAt: lastAppRefreshAt, onRefreshStatus: onRefreshStatus)

                Text("フィルタ")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PortalSectionStyle.all, id: \.name) { section in
                            FilterChip(
                                title: section.name,
                                color: section.color,
                                isSelected: selectedSection == section.name
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSection = section.name
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("左右スワイプで種別を切り替え")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(sectionColor)
                        .frame(width: 8, height: 8)
                    Text(section)
                        .font(.headline)
                    Spacer()
                    Text("\(notices.count)件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if notices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isGlobalEmpty ? "Firestoreから取得中、またはデータがありません。" : "この種別に一致するお知らせはありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let errorMessage, isGlobalEmpty {
                            Text("エラー: \(errorMessage)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(notices) { notice in
                        NotificationCard(notice: notice)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

struct SessionExpiredBanner: View {
    let status: PortalStatus
    let onRefreshStatus: () -> Void
    private let reauthCommand = "cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend && ./reauth_and_sync.sh"
    private let verifyCommand = "cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend && source .venv/bin/activate && python src/run_once.py"
    @State private var showRecoveryFlow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ポータル再認証が必要です", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("通知取得が停止中です。iPhoneだけでは再認証を完了できないため、Macで1回だけ再認証してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showRecoveryFlow = true
            } label: {
                Label("復旧フローを開く", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
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
        .sheet(isPresented: $showRecoveryFlow) {
            RecoveryFlowSheet(
                reauthCommand: reauthCommand,
                verifyCommand: verifyCommand,
                onRefreshStatus: onRefreshStatus
            )
        }
    }
}

struct RecoveryFlowSheet: View {
    let reauthCommand: String
    let verifyCommand: String
    let onRefreshStatus: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPortalLogin = false

    var body: some View {
        NavigationStack {
            List {
                Section("1. アプリ内でMicrosoftログイン") {
                    Text("まずこのアプリ内ブラウザでログインを完了します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showPortalLogin = true
                    } label: {
                        Label("アプリ内でログインを開く", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }

                Section("2. Macで再認証+同期を実行") {
                    Text(reauthCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = reauthCommand
                    } label: {
                        Label("再認証コマンドをコピー", systemImage: "doc.on.doc")
                    }
                }

                Section("3. 再認証後に同期状態を確認") {
                    Text(verifyCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = verifyCommand
                    } label: {
                        Label("確認コマンドをコピー", systemImage: "doc.on.doc")
                    }
                    Button {
                        onRefreshStatus()
                    } label: {
                        Label("同期状態を再確認", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("復旧フロー")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showPortalLogin) {
                PortalLoginSheet()
            }
        }
    }
}

struct SyncStatusCard: View {
    let status: PortalStatus?
    let lastAppRefreshAt: Date?
    let onRefreshStatus: () -> Void

    private var appRefreshLabel: String? {
        guard let lastAppRefreshAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter.string(from: lastAppRefreshAt)
    }

    var body: some View {
        if let status {
            if status.authRequired {
                SessionExpiredBanner(status: status, onRefreshStatus: onRefreshStatus)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("同期は正常です", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if let checkedAt = status.checkedAtLabel {
                        Text("バックエンド最終確認: \(checkedAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let appRefreshLabel {
                        Text("アプリ再確認: \(appRefreshLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
                Button {
                    onRefreshStatus()
                } label: {
                    Label("同期状態を再確認", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("同期状態を確認中", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("バックエンド状態を取得しています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
    }
}

struct PortalLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let startURL = URL(string: "https://websrv.tcu.ac.jp/tcu_web_v3/top.do")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PortalSafariView(url: startURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text("このSafari画面でMicrosoft認証を完了してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        openURL(startURL)
                    } label: {
                        Label("外部Safariで開く", systemImage: "safari")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("ポータル再ログイン")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct PortalSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // no-op
    }
}
