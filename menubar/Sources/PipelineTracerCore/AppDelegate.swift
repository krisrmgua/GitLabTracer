import AppKit
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var menuController: MenuController!

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "PipelineTracer", withExtension: "icns"),
           let image = NSImage(contentsOf: icon) {
            NSApp.applicationIconImage = image
        }
        UNUserNotificationCenter.current().delegate = self
        if CommandLine.arguments.contains("--notify") {
            // Live alerts from the Electron app. Same banner path as Send test.
            NSApp.setActivationPolicy(.accessory)
            Notifier.requestAuthorization { granted in
                guard granted, Notifier.postFromCommandLine() else {
                    fputs("Enable Pipeline Tracer notifications in macOS Notifications settings first.\n", stderr)
                    exit(2)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Notifier.autoDismissSeconds + 8) {
                fputs("Notification timed out.\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--notification-preview") {
            // Headless test path used by the Electron app. Exit after queueing.
            NSApp.setActivationPolicy(.accessory)
            Notifier.requestAuthorization { granted in
                guard granted else {
                    fputs("Enable Pipeline Tracer notifications in macOS Notifications settings first.\n", stderr)
                    exit(2)
                }
                Notifier.preview()
                print("Pipeline Tracer test notification queued.")
                // Stay alive until auto-dismiss clears the banner.
                DispatchQueue.main.asyncAfter(deadline: .now() + Notifier.autoDismissSeconds + 1.5) { exit(0) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Notifier.autoDismissSeconds + 8) {
                fputs("Notification preview timed out.\n", stderr)
                exit(1)
            }
            return
        }
        if Bundle.main.bundlePath.contains("NotificationPreview.app") {
            // A banner click relaunches this helper. Open the link and do not start a second menu.
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuController = MenuController(statusItem: statusItem)
        menuController.start()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even while this process is frontmost (Send test / live alerts).
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { completionHandler(); return }
        if let value = response.notification.request.content.userInfo["url"] as? String,
           let url = Shell.browserURL(value) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
        if Bundle.main.bundlePath.contains("NotificationPreview.app") {
            NSApp.terminate(nil)
        }
    }
}
