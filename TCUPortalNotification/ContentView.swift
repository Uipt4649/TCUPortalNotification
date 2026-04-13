//
//  TCUPortalNotificationApp.swift
//  ContentView
//
//  Created by 渡邉羽唯 on 2026/04/04.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = NoticeStore()

    var body: some View {
        TabView {
            NavigationStack {
                InboxView(
                    notices: store.notices,
                    errorMessage: store.errorMessage,
                    portalStatus: store.portalStatus,
                    lastAppRefreshAt: store.lastAppRefreshAt,
                    onRefreshStatus: { store.refreshNow() }
                )
            }
            .tabItem { Label("受信箱", systemImage: "tray.full") }

            NavigationStack {
                ImportantView(notices: store.notices)
            }
            .tabItem { Label("重要", systemImage: "exclamationmark.circle") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .onAppear { store.startListening() }
    }
}

#Preview {
    ContentView()
}
