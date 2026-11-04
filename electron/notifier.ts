import { app, nativeImage, Notification, shell, type NativeImage } from "electron";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { appIconPng } from "./icons";
import { browserURL, notificationContent, type NotificationKind } from "./logic";

// Keeps a reference so a clicked banner can still reach its handler after GC would collect it.
const live = new Set<Notification>();

let cachedIcon: NativeImage | null = null;
let cachedIconPath: string | null = null;

export function notificationsSupported(): boolean {
  return Notification.isSupported();
}

/** App mark for banners. Prefer the packaged icns/png; fall back to a generated PNG. */
function notificationIcon(): { image: NativeImage; path: string | null } {
  if (cachedIcon && !cachedIcon.isEmpty()) {
    return { image: cachedIcon, path: cachedIconPath };
  }

  const candidates = [
    path.join(process.resourcesPath, "icon.icns"),
    path.join(process.resourcesPath, "icon.png"),
    path.join(app.getAppPath(), "assets", "icon.png"),
  ];
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    const img = nativeImage.createFromPath(file);
    if (img.isEmpty()) continue;
    cachedIcon = img;
    cachedIconPath = file.endsWith(".png") ? file : null;
    break;
  }

  if (!cachedIcon || cachedIcon.isEmpty()) {
    cachedIcon = nativeImage.createFromBuffer(appIconPng(128));
    cachedIconPath = null;
  }

  // Electron on macOS often wants a file path for Notification.icon.
  if (!cachedIconPath) {
    const tmp = path.join(os.tmpdir(), "pipeline-tracer-notification-icon.png");
    try {
      fs.writeFileSync(tmp, cachedIcon.toPNG());
      cachedIconPath = tmp;
    } catch {
      cachedIconPath = null;
    }
  }

  return { image: cachedIcon, path: cachedIconPath };
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
  const { image, path: iconPath } = notificationIcon();
  const n = new Notification({
    title: content.title,
    // Windows toasts have no subtitle line, so the event title leads the body there.
    subtitle: isMac ? content.subtitle : undefined,
    body: isMac ? content.body : `${content.subtitle}\n${content.body}`,
    silent: !content.sound,
    urgency: content.urgent ? "critical" : "normal",
    timeoutType: content.urgent && process.platform === "win32" ? "never" : "default",
    icon: iconPath ?? image,
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

export interface PreviewResult {
  ok: boolean;
  message: string;
}

/**
 * Send-test path. Caller should hide the panel first on macOS — the OS suppresses
 * banners for the frontmost app.
 */
export async function preview(): Promise<PreviewResult> {
  if (!Notification.isSupported()) {
    return {
      ok: false,
      message: "Notifications are not supported on this system.",
    };
  }

  const content = notificationContent(
    "Preview · Merge complete",
    "example/project · !347",
    "Fix calendar cell count for the current month",
    "pipeline-tracer-preview",
    false,
    "https://gitlab.com",
    "mergeRequest",
  );
  const isMac = process.platform === "darwin";
  const { image, path: iconPath } = notificationIcon();
  const n = new Notification({
    title: content.title,
    subtitle: isMac ? content.subtitle : undefined,
    body: isMac ? content.body : `${content.subtitle}\n${content.body}`,
    silent: true,
    icon: iconPath ?? image,
  });
  live.add(n);

  const shown = await new Promise<boolean>((resolve) => {
    let settled = false;
    const done = (ok: boolean) => {
      if (settled) return;
      settled = true;
      resolve(ok);
    };
    n.once("show", () => done(true));
    n.once("failed", () => done(false));
    n.once("close", () => {
      // Some platforms fire close without show when delivery is blocked.
      setTimeout(() => done(false), 0);
    });
    n.show();
    setTimeout(() => done(false), 1500);
  });

  // Keep the ref briefly so the banner can paint, then drop it with the rest.
  setTimeout(() => live.delete(n), 8000);

  if (shown) {
    return { ok: true, message: "Test notification sent." };
  }
  return {
    ok: false,
    message:
      "Could not show a notification. Enable Pipeline Tracer in System Settings → Notifications (and turn Focus off), then try again.",
  };
}
