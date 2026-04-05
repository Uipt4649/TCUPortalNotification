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
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
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
