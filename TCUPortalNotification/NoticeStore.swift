import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

final class NoticeStore: ObservableObject {
    @Published var notices: [NoticeItem] = []
    @Published var errorMessage: String?
    @Published var portalStatus: PortalStatus?

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
    private var listener: ListenerRegistration?
    private var statusListener: ListenerRegistration?
#endif
    private var hasBootstrapped = false
    private var knownIDs: Set<String> = []
    private let knownIDsKey = "known_notice_ids"

    init() {
        if let cached = UserDefaults.standard.array(forKey: knownIDsKey) as? [String] {
            knownIDs = Set(cached)
        }
    }

    func startListening() {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        guard listener == nil else { return }
        LocalNoticeNotifier.shared.requestAuthorization()

        listener = Firestore.firestore()
            .collection("notices")
            .whereField("source", isEqualTo: "portal_message_list")
            .limit(to: 300)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }

                let docs = snapshot?.documents ?? []
                let mapped = docs
                    .compactMap(NoticeItem.init(document:))
                    .sorted(by: { $0.receivedAtEpoch > $1.receivedAtEpoch })
                let mappedIDs = Set(mapped.map { $0.id })
                let newIDs: Set<String>

                if self.hasBootstrapped {
                    newIDs = mappedIDs.subtracting(self.knownIDs)
                } else {
                    newIDs = []
                    self.hasBootstrapped = true
                }

                self.knownIDs.formUnion(mappedIDs)
                UserDefaults.standard.set(Array(self.knownIDs), forKey: self.knownIDsKey)

                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.notices = mapped
                }

                if !newIDs.isEmpty {
                    let newNotices = mapped.filter { newIDs.contains($0.id) }
                    for notice in newNotices {
                        LocalNoticeNotifier.shared.notifyNewNotice(notice)
                    }
                }
            }

        statusListener = Firestore.firestore()
            .collection("system_status")
            .document("portal_auth")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async { self.portalStatus = nil }
                    return
                }
                DispatchQueue.main.async { self.portalStatus = PortalStatus(data: data) }
            }
#endif
    }

    func refreshPortalStatusOnce() {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        Firestore.firestore()
            .collection("system_status")
            .document("portal_auth")
            .getDocument { [weak self] snapshot, _ in
                guard let self else { return }
                guard let data = snapshot?.data() else { return }
                DispatchQueue.main.async {
                    self.portalStatus = PortalStatus(data: data)
                }
            }
#endif
    }

    func refreshNow() {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let group = DispatchGroup()

        var fetchedNotices: [NoticeItem]?
        var fetchedStatus: PortalStatus?
        var fetchError: String?

        group.enter()
        db.collection("notices")
            .whereField("source", isEqualTo: "portal_message_list")
            .limit(to: 300)
            .getDocuments(source: .server) { snapshot, error in
                defer { group.leave() }
                if let error {
                    fetchError = error.localizedDescription
                    return
                }
                let docs = snapshot?.documents ?? []
                fetchedNotices = docs
                    .compactMap(NoticeItem.init(document:))
                    .sorted(by: { $0.receivedAtEpoch > $1.receivedAtEpoch })
            }

        group.enter()
        db.collection("system_status")
            .document("portal_auth")
            .getDocument(source: .server) { snapshot, error in
                defer { group.leave() }
                if let error {
                    fetchError = error.localizedDescription
                    return
                }
                if let data = snapshot?.data() {
                    fetchedStatus = PortalStatus(data: data)
                }
            }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let fetchedNotices {
                self.notices = fetchedNotices
                let ids = Set(fetchedNotices.map { $0.id })
                self.knownIDs.formUnion(ids)
                UserDefaults.standard.set(Array(self.knownIDs), forKey: self.knownIDsKey)
            }
            if let fetchedStatus {
                self.portalStatus = fetchedStatus
            }
            if let fetchError {
                self.errorMessage = fetchError
            } else {
                self.errorMessage = nil
            }
        }
#endif
    }
}

final class LocalNoticeNotifier {
    static let shared = LocalNoticeNotifier()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func notifyNewNotice(_ notice: NoticeItem) {
        let content = UNMutableNotificationContent()
        content.title = "新着 [\(notice.course)] \(notice.title)"
        content.body = notice.summary
        content.sound = .default

        let request = UNNotificationRequest(identifier: "notice-\(notice.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
