import SwiftUI
import Combine
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

struct SettingsView: View {
    @State private var pushEnabled = true
    @State private var classCancelEnabled = true
    @State private var assignmentEnabled = true
    @State private var quietModeEnabled = true
    @StateObject private var pushState = PushDebugState.shared

    var body: some View {
        Form {
            Section("通知") {
                Toggle("プッシュ通知", isOn: $pushEnabled)
                Toggle("休講・教室変更", isOn: $classCancelEnabled)
                Toggle("課題通知", isOn: $assignmentEnabled)
            }

            Section("プッシュ接続状態") {
                HStack {
                    Text("通知許可")
                    Spacer()
                    Text(pushState.authorizationLabel)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("FCMトークン")
                    Spacer()
                    Text(pushState.tokenLabel)
                        .foregroundStyle(.secondary)
                }
                if let message = pushState.lastErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("通知設定を再確認") {
                    pushState.refreshAll()
                }
            }

            Section("時間帯") {
                Toggle("深夜ミュート (23:00-07:00)", isOn: $quietModeEnabled)
            }
        }
        .navigationTitle("設定")
        .onAppear {
            pushState.refreshAll()
        }
    }
}

final class PushDebugState: ObservableObject {
    static let shared = PushDebugState()

    @Published var authorizationLabel: String = "未確認"
    @Published var tokenLabel: String = "未取得"
    @Published var lastErrorMessage: String?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .pushTokenDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let token = (note.userInfo?["token"] as? String) ?? ""
            self?.tokenLabel = token.isEmpty ? "未取得" : "保存済み"
            self?.lastErrorMessage = nil
        }
        NotificationCenter.default.addObserver(
            forName: .pushTokenSaveDidFail,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.lastErrorMessage = note.userInfo?["message"] as? String
        }
        NotificationCenter.default.addObserver(
            forName: .apnsRegistrationDidFail,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.lastErrorMessage = note.userInfo?["message"] as? String
        }
    }

    func refreshAll() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.authorizationLabel = "許可"
                case .denied:
                    self.authorizationLabel = "拒否"
                case .notDetermined:
                    self.authorizationLabel = "未選択"
                default:
                    self.authorizationLabel = "不明"
                }
            }
        }

#if canImport(FirebaseMessaging)
        Messaging.messaging().token { token, error in
            DispatchQueue.main.async {
                if let error {
                    self.lastErrorMessage = "FCM token取得失敗: \(error.localizedDescription)"
                    return
                }
                guard let token, !token.isEmpty else {
                    self.tokenLabel = "未取得"
                    return
                }
                self.tokenLabel = "取得済み"
                DeviceTokenStore.shared.save(fcmToken: token)
            }
        }
#else
        DispatchQueue.main.async {
            self.lastErrorMessage = "FirebaseMessaging 未導入"
        }
#endif
    }
}

