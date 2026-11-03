import AppKit
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var menuController: MenuController!

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "PipelineTracer", withExtension: "icns"),
           let image = NSImage(contentsOf: icon) {
            NSApp.applicationIconImage = image
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuController = MenuController(statusItem: statusItem)
        UNUserNotificationCenter.current().delegate = self
        if CommandLine.arguments.contains("--notification-preview") {
            Notifier.requestAuthorization { granted in
                if granted { Notifier.preview() }
            }
            return
        }
        menuController.start()
    }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { completionHandler(); return }
        if let value = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: value), url.scheme == "https", url.host == "gitlab.com" {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
