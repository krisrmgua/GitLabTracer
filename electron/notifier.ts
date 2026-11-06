import { app, nativeImage, Notification, shell, type NativeImage } from "electron";
import { execFile } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { appIconPng } from "./icons";
import { browserURL, notificationContent, type NotificationKind } from "./logic";

const execFileAsync = promisify(execFile);

// Keeps a reference so a clicked banner can still reach its handler after GC would collect it.
const live = new Set<Notification>();

let cachedIcon: NativeImage | null = null;
let cachedIconPath: string | null = null;

export function notificationsSupported(): boolean {
  return Notification.isSupported() || process.platform === "darwin";
}

/** App mark for banners. Prefer the packaged icns/png; fall back to a generated PNG. */
function notificationIcon(): { image: NativeImage; path: string | null } {
  if (cachedIcon && !cachedIcon.isEmpty()) {
    return { image: cachedIcon, path: cachedIconPath };
  }

  const candidates = [
    path.join(process.resourcesPath, "icon.icns"),
    path.join(process.resourcesPath, "icon.png"),
    path.join(process.resourcesPath, "NotificationPreview.app", "Contents", "Resources", "PipelineTracer.icns"),
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

/** Swift helper that posts via UNUserNotificationCenter (reliable banners + app icon). */
function swiftPreviewBinary(): string | null {
  const candidates = [
    path.join(process.resourcesPath, "NotificationPreview.app", "Contents", "MacOS", "PipelineTracer"),
    path.join(app.getAppPath(), "menubar", "Pipeline Tracer.app", "Contents", "MacOS", "PipelineTracer"),
    path.join(process.cwd(), "menubar", "Pipeline Tracer.app", "Contents", "MacOS", "PipelineTracer"),
  ];
  return candidates.find((file) => fs.existsSync(file)) ?? null;
}

async function sendViaSwiftPreview(): Promise<PreviewResult | null> {
  if (process.platform !== "darwin") return null;
  const bin = swiftPreviewBinary();
  if (!bin) return null;
  try {
    const { stdout, stderr } = await execFileAsync(bin, ["--notification-preview"], {
      // Helper stays alive through the 6s auto-dismiss window.
      timeout: 20_000,
      encoding: "utf8",
    });
    if (/Enable Pipeline Tracer notifications/i.test(stderr || "")) {
      return {
        ok: false,
        message:
          "Enable Pipeline Tracer in System Settings → Notifications, then try again.",
      };
    }
    if ((stdout || "").includes("queued") || (stdout || "").includes("preview")) {
      return { ok: true, message: "Test notification sent." };
    }
    return { ok: true, message: "Test notification sent." };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (/Enable Pipeline Tracer notifications/i.test(msg) || /exit code 2/i.test(msg)) {
      return {
        ok: false,
        message:
          "Enable Pipeline Tracer in System Settings → Notifications, then try again.",
      };
    }
    return null;
  }
}

async function sendViaOsascript(body: string): Promise<boolean> {
  if (process.platform !== "darwin") return false;
  try {
    await execFileAsync(
      "osascript",
      [
        "-e",
        `display notification ${JSON.stringify(body)} with title "Pipeline Tracer" subtitle "Notification preview"`,
      ],
      { timeout: 5000 },
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Banners are titled Pipeline Tracer. Failures play the default sound and ask for critical
 * urgency where the OS honors it. Clicking opens the event's GitLab or GitHub page.
 */
function showElectron(content: ReturnType<typeof notificationContent>): void {
  if (!Notification.isSupported()) return;
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
  // macOS Alert-style prefs leave banners until dismissed; close after a short linger.
  setTimeout(() => {
    try {
      n.close();
    } catch {
      /* already gone */
    }
    release();
  }, 6000);
}

/** macOS live alerts use the same UserNotifications helper as Send test. */
function sendLiveViaSwift(content: ReturnType<typeof notificationContent>): boolean {
  const bin = swiftPreviewBinary();
  if (!bin) return false;
  execFile(
    bin,
    ["--notify", content.subtitle, "", content.body, content.thread, content.url, content.kind, content.sound ? "1" : "0"],
    { timeout: 20_000 },
    (err) => {
      if (err) showElectron(content);
    },
  );
  return true;
}

export function post(
  title: string,
  subtitle: string,
  body: string,
  thread: string,
  important: boolean,
  url: string,
  kind: NotificationKind,
): void {
  const content = notificationContent(title, subtitle, body, thread, important, url, kind);
  if (process.platform === "darwin" && sendLiveViaSwift(content)) return;
  showElectron(content);
}

export interface PreviewResult {
  ok: boolean;
  message: string;
}

/**
 * Send-test path. Caller should hide the panel first on macOS — the OS suppresses
 * banners for the frontmost app. Prefers the Swift UNUserNotificationCenter helper
 * (same icon as the app), then Electron, then osascript.
 */
export async function preview(): Promise<PreviewResult> {
  const viaSwift = await sendViaSwiftPreview();
  if (viaSwift) return viaSwift;

  if (Notification.isSupported()) {
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
      silent: false,
      icon: iconPath ?? image,
    });
    live.add(n);

    let failed = false;
    n.once("failed", () => {
      failed = true;
    });
    n.show();
    // macOS often never fires "show"; treat as delivered unless "failed" arrives.
    await new Promise((r) => setTimeout(r, 600));
    setTimeout(() => {
      try {
        n.close();
      } catch {
        /* already gone */
      }
      live.delete(n);
    }, 6000);

    if (!failed) {
      return { ok: true, message: "Test notification sent." };
    }
  }

  const body =
    "example/project · !347 · Fix calendar cell count for the current month";
  if (await sendViaOsascript(body)) {
    return { ok: true, message: "Test notification sent." };
  }

  return {
    ok: false,
    message:
      "Could not show a notification. Enable Pipeline Tracer in System Settings → Notifications (and turn Focus off), then try again.",
  };
}
