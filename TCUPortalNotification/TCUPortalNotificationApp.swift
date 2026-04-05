//
//  TCUPortalNotificationApp.swift
//  TCUPortalNotification
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

extension Notification.Name {
    static let pushTokenDidUpdate = Notification.Name("pushTokenDidUpdate")
    static let pushTokenSaveDidFail = Notification.Name("pushTokenSaveDidFail")
    static let apnsRegistrationDidFail = Notification.Name("apnsRegistrationDidFail")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if canImport(FirebaseCore)
        FirebaseApp.configure()
#else
        // FirebaseCore is not available. Skipping configuration to avoid build errors.
        // Add Firebase to the project (Swift Package Manager or CocoaPods) and remove this guard.
        print("[Info] FirebaseCore not found. Skipping Firebase configuration.")
#endif
        UNUserNotificationCenter.current().delegate = self
#if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
#endif
        DeviceTokenStore.shared.observePushPermission()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
#if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error {
                NotificationCenter.default.post(
                    name: .pushTokenSaveDidFail,
                    object: nil,
                    userInfo: ["message": "FCM token取得失敗: \(error.localizedDescription)"]
                )
                return
            }
            guard let token, !token.isEmpty else { return }
            DeviceTokenStore.shared.save(fcmToken: token)
        }
#endif
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .apnsRegistrationDidFail,
            object: nil,
            userInfo: ["message": "APNs登録失敗: \(error.localizedDescription)"]
        )
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        DeviceTokenStore.shared.save(fcmToken: fcmToken)
        print("[Info] FCM token received")
    }
}
#endif

final class DeviceTokenStore {
    static let shared = DeviceTokenStore()

    private init() {}

    func observePushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func save(fcmToken: String) {
#if canImport(FirebaseFirestore)
        let payload: [String: Any] = [
            "token": fcmToken,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        Firestore.firestore().collection("device_tokens").document(fcmToken).setData(payload, merge: true) { error in
            if let error {
                NotificationCenter.default.post(
                    name: .pushTokenSaveDidFail,
                    object: nil,
                    userInfo: ["message": "Firestore保存失敗: \(error.localizedDescription)"]
                )
                return
            }
            NotificationCenter.default.post(
                name: .pushTokenDidUpdate,
                object: nil,
                userInfo: ["token": fcmToken]
            )
        }
#else
        NotificationCenter.default.post(
            name: .pushTokenSaveDidFail,
            object: nil,
            userInfo: ["message": "FirebaseFirestore 未導入"]
        )
#endif
    }
}

@main
struct TCUPortalNotificationApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
