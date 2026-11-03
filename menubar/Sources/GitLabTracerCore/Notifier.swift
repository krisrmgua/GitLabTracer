import Foundation
import UserNotifications

/// macOS notifications for pipeline events: a job finishing, a pipeline finishing, a new pipeline.
enum Notifier {
    enum Kind: String, CaseIterable {
        case pipeline, logs, mergeRequest, readyMergeRequest
        var actionTitle: String {
            switch self { case .pipeline: return "View pipeline"; case .logs: return "View logs"; case .mergeRequest: return "View MR"; case .readyMergeRequest: return "Review MR" }
        }
    }

    static func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        let categories = Kind.allCases.map { kind in
            UNNotificationCategory(identifier: kind.rawValue,
                actions: [UNNotificationAction(identifier: "open", title: kind.actionTitle, options: [.foreground])],
                intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("GitLab Tracer notification authorization failed: %@", error.localizedDescription) }
            if CommandLine.arguments.contains("--notification-preview") { NSLog("GitLab Tracer notification permission granted: %@", String(granted)) }
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func checkPermission(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let enabled = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            DispatchQueue.main.async { completion(enabled) }
        }
    }

    static func preview() {
        post("Preview · Merge complete", subtitle: "example/project · !347",
             body: "Fix calendar cell count for the current month", thread: "gitlab-tracer-preview",
             url: "https://gitlab.com", kind: .mergeRequest)
    }

    /// Collapse whitespace and bound banner copy; full details remain in the inbox.
    static func compact(_ text: String, limit: Int = 90) -> String {
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return line.count > limit ? String(line.prefix(max(0, limit - 1))) + "…" : line
    }

    static func content(_ title: String, subtitle: String, body: String, thread: String,
                        important: Bool, url: String, kind: Kind) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "GitLab Tracer"
        content.subtitle = compact(title, limit: 80)
        let detail = [subtitle, body].map { compact($0, limit: 180) }.filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = compact(detail)
        content.threadIdentifier = thread
        content.categoryIdentifier = kind.rawValue
        content.sound = important ? .default : nil
        // macOS draws banner text itself, so a failure cannot be colored red.
        // The sound is the extra signal. Time sensitive is requested; without
        // Apple's entitlement the system delivers it as a normal banner.
        if important {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        }
        content.userInfo = ["url": url]
        return content
    }

    static func post(_ title: String, subtitle: String, body: String, thread: String,
                     important: Bool = false, url: String, kind: Kind) {
        let content = content(title, subtitle: subtitle, body: body, thread: thread,
                              important: important, url: url, kind: kind)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("GitLab Tracer notification delivery failed: %@", error.localizedDescription) }
        }
    }

    /// Statuses that mean "not finished yet".
    static func isActive(_ status: String) -> Bool {
        ["running", "pending", "created", "preparing", "waiting_for_resource", "scheduled"].contains(status)
    }

    static func isDone(_ status: String) -> Bool {
        ["success", "passed", "failed", "canceled", "cancelled", "skipped"].contains(status)
    }
}
