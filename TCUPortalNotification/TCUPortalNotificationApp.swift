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
#endif
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

private final class DeviceTokenStore {
    static let shared = DeviceTokenStore()

    private init() {}

    func save(fcmToken: String) {
#if canImport(FirebaseFirestore)
        let payload: [String: Any] = [
            "token": fcmToken,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        Firestore.firestore().collection("device_tokens").document(fcmToken).setData(payload, merge: true)
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
