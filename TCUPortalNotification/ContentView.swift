import SwiftUI

struct ContentView: View {
    @StateObject private var store = NoticeStore()

    var body: some View {
        TabView {
            NavigationStack {
                InboxView(
                    notices: store.notices,
                    errorMessage: store.errorMessage,
                    portalStatus: store.portalStatus
                )
            }
            .tabItem { Label("受信箱", systemImage: "tray.full") }

            NavigationStack {
                ImportantView(notices: store.notices)
            }
            .tabItem { Label("重要", systemImage: "exclamationmark.circle") }

            NavigationStack {
                CalendarView(notices: store.notices)
            }
            .tabItem { Label("カレンダー", systemImage: "calendar") }

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
