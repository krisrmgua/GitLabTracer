import { Notification, shell } from "electron";
import { browserURL, notificationContent, type NotificationKind } from "./logic";

// Keeps a reference so a clicked banner can still reach its handler after GC would collect it.
const live = new Set<Notification>();

export function notificationsSupported(): boolean {
  return Notification.isSupported();
}

/**
 * Banners are titled Pipeline Tracer. Failures play the default sound and ask for critical
 * urgency where the OS honors it. Clicking opens the event's GitLab or GitHub page.
 */
export function post(
  title: string,
  subtitle: string,
  body: string,
  thread: string,
  important: boolean,
  url: string,
  kind: NotificationKind,
): void {
  if (!Notification.isSupported()) return;
  const content = notificationContent(title, subtitle, body, thread, important, url, kind);
  const isMac = process.platform === "darwin";
  const n = new Notification({
    title: content.title,
    // Windows toasts have no subtitle line, so the event title leads the body there.
    subtitle: isMac ? content.subtitle : undefined,
    body: isMac ? content.body : `${content.subtitle}\n${content.body}`,
    silent: !content.sound,
    urgency: content.urgent ? "critical" : "normal",
    timeoutType: content.urgent && process.platform === "win32" ? "never" : "default",
  });
  live.add(n);
  const release = () => live.delete(n);
  n.on("click", () => {
    const target = browserURL(content.url);
    if (target) void shell.openExternal(target);
    release();
  });
  n.on("close", release);
  n.on("failed", release);
  n.show();
}

export function preview(): void {
  post(
    "Preview · Merge complete",
    "example/project · !347",
    "Fix calendar cell count for the current month",
    "pipeline-tracer-preview",
    false,
    "https://gitlab.com",
    "mergeRequest",
  );
}
