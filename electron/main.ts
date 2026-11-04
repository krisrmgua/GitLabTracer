import { app, BrowserWindow, clipboard, ipcMain, Menu, nativeImage, screen, shell, Tray } from "electron";
import path from "node:path";
import { Controller } from "./controller";
import { trayIconPng } from "./icons";
import {
  browserURL,
  mrKey,
  pipelineKey,
  progressState,
  refLabel,
  trayCounts,
  isDone,
  type Job,
  type MergeRequest,
  type Pipeline,
  type Prefs,
} from "./logic";
import * as model from "./model";
import * as notifier from "./notifier";
import { discoverPath } from "./shell";
import { Store } from "./store";

const APP_ID = "com.kris.pipelinetracer";
const isDev = process.env.PIPELINE_TRACER_DEV === "1";
const isMac = process.platform === "darwin";

const INBOX_WIDTH = 430;
const MIN_HEIGHT = 160;
const MAX_HEIGHT = 700;

let tray: Tray | null = null;
let panel: BrowserWindow | null = null;
let store: Store;
let controller: Controller;
let lastTrayKey = "";

function panelUrl(): string {
  if (isDev) return "http://127.0.0.1:5173";
  return `file://${path.join(app.getAppPath(), "dist", "index.html")}`;
}

function createPanel(): BrowserWindow {
  const win = new BrowserWindow({
    width: INBOX_WIDTH,
    height: 450,
    show: false,
    frame: false,
    resizable: false,
    useContentSize: true,
    skipTaskbar: true,
    alwaysOnTop: true,
    fullscreenable: false,
    backgroundColor: "#0e1a29",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  void win.loadURL(panelUrl());
  // Clicking away closes the panel, like the Swift popover.
  win.on("blur", () => {
    if (!isDev) win.hide();
  });
  win.on("hide", () => win.webContents.send("tracer:hidden"));
  // Links inside the panel never navigate the panel itself.
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (e, url) => {
    if (url !== panelUrl()) e.preventDefault();
  });
  return win;
}

function maxPanelHeight(): number {
  const point = tray ? tray.getBounds() : screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint({ x: point.x, y: point.y });
  return Math.min(MAX_HEIGHT, display.workArea.height - 40);
}

function fitPanel(width: number, height: number): void {
  if (!panel) return;
  const w = Math.round(Math.min(Math.max(width, 320), 720));
  const h = Math.round(Math.min(Math.max(height, MIN_HEIGHT), maxPanelHeight()));
  const [cw, ch] = panel.getContentSize();
  if (cw === w && ch === h) return;
  panel.setContentSize(w, h);
  if (panel.isVisible()) positionPanel(panel);
}

function positionPanel(win: BrowserWindow): void {
  if (!tray) return;
  const trayBounds = tray.getBounds();
  const winBounds = win.getBounds();
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y });
  const wa = display.workArea;
  let x = Math.round(trayBounds.x + trayBounds.width / 2 - winBounds.width / 2);
  // macOS: under the menu bar. Windows: above the taskbar, or below it when the taskbar is on top.
  const taskbarOnTop = !isMac && trayBounds.y < wa.y + wa.height / 2;
  let y =
    isMac || taskbarOnTop
      ? Math.round(trayBounds.y + trayBounds.height + 4)
      : Math.round(trayBounds.y - winBounds.height - 4);
  x = Math.min(Math.max(x, wa.x + 8), wa.x + wa.width - winBounds.width - 8);
  y = Math.min(Math.max(y, wa.y + 8), wa.y + wa.height - winBounds.height - 8);
  win.setPosition(x, y, false);
}

function togglePanel(): void {
  if (!panel) panel = createPanel();
  if (panel.isVisible()) {
    panel.hide();
    return;
  }
  positionPanel(panel);
  panel.show();
  panel.focus();
  panel.webContents.send("tracer:shown");
  void controller.refresh();
}

function broadcast(): void {
  updateTray();
  panel?.webContents.send("tracer:state", controller.snapshot());
}

function trayImage(failing: boolean): Electron.NativeImage {
  const [status, progress] = progressState(controller.cardPipeline);
  // Rendered at 2x and marked as such, so the menu bar and HiDPI trays stay sharp.
  const size = isMac ? 18 : 16;
  const image = nativeImage.createEmpty();
  image.addRepresentation({ scaleFactor: 1, width: size, height: size, buffer: trayIconPng(status, progress, failing, size) });
  image.addRepresentation({ scaleFactor: 2, width: size * 2, height: size * 2, buffer: trayIconPng(status, progress, failing, size * 2) });
  return image;
}

/** Menu bar text: open requests, running and failed pipelines. Fail is red and bold. */
function trayTitle(requests: number, running: number, failed: number): string {
  const reset = "\u001b[0m";
  const parts: string[] = [];
  if (requests > 0) parts.push(`MR ${requests}`);
  if (running > 0) parts.push(`\u001b[36mRun ${running}${reset}`);
  if (failed > 0) parts.push(`\u001b[1;31mFail ${failed}${reset}`);
  return parts.join(" │ ");
}

function updateTray(): void {
  if (!tray || !controller) return;
  const { requests, running, failed } = trayCounts(controller.pipelines, controller.mrs);
  const [status, progress] = progressState(controller.cardPipeline);
  const failing = failed > 0;
  const key = `${status}|${progress.toFixed(2)}|${failing}`;
  if (key !== lastTrayKey) {
    lastTrayKey = key;
    tray.setImage(trayImage(failing));
  }
  if (isMac) tray.setTitle(trayTitle(requests, running, failed), { fontType: "monospacedDigit" });

  const lines = [`Pipeline Tracer: ${requests} requests · ${running} running · ${failed} failed`];
  const p = controller.cardPipeline;
  if (p) {
    const done = p.jobs.filter((j) => isDone(j.status)).length;
    lines.push(`${p.project} #${p.id} · ${refLabel(p)}`, p.jobs.length ? `${p.status} · ${done}/${p.jobs.length} jobs finished` : p.status);
  } else {
    lines.push("No recent pipelines");
  }
  // Windows caps tray tooltips at 127 characters.
  const tip = lines.join("\n");
  tray.setToolTip(isMac ? tip : tip.slice(0, 127));
}

function applyLoginItem(prefs: Prefs): void {
  if (!app.isPackaged) return;
  if (process.platform !== "darwin" && process.platform !== "win32") return;
  app.setLoginItemSettings({ openAtLogin: prefs.startAtLogin });
}

const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);

function findPipeline(key: unknown): Pipeline | null {
  if (typeof key !== "string") return null;
  return controller.pipelines.find((p) => pipelineKey(p) === key) ?? null;
}

/** The panel sends keys, never raw API paths; requests come from the main process's own snapshot. */
function findRequest(key: unknown, sha: unknown): MergeRequest | null {
  if (typeof key !== "string") return null;
  const mr = controller.mrs.find((m) => mrKey(m) === key);
  if (!mr) return null;
  // The SHA the user reviewed in the detail view wins, so a push since then blocks the merge.
  return typeof sha === "string" && /^[0-9a-f]{7,64}$/i.test(sha) ? { ...mr, sha } : mr;
}

function wireIpc(): void {
  ipcMain.handle("tracer:getState", () => controller.snapshot());

  ipcMain.handle("tracer:refresh", () => {
    controller.schedule();
    void controller.refresh();
  });

  ipcMain.handle("tracer:setPrefs", (_e, input: Partial<Prefs>) => {
    const before = store.prefs;
    const after = store.setPrefs(input ?? {});
    applyLoginItem(after);
    controller.prefsChanged(before, after);
    return after;
  });

  ipcMain.handle("tracer:jobs", async (_e, key: unknown, force: unknown) => {
    const p = findPipeline(key);
    if (!p) return null;
    return model.jobsForPipeline(p, force === true);
  });

  ipcMain.handle("tracer:log", async (_e, key: unknown, job: Job) => {
    const p = findPipeline(key);
    if (!p || !job || !isInt(job.id)) return null;
    return model.jobTrace(job, p);
  });

  ipcMain.handle("tracer:mrDetail", async (_e, key: unknown) => {
    const mr = findRequest(key, null);
    return mr ? model.mrDetail(mr) : null;
  });

  ipcMain.handle("tracer:merge", (_e, key: unknown, sha: unknown) => {
    const mr = findRequest(key, sha);
    if (!mr || !store.prefs.mergeButton) return false;
    controller.merge(mr);
    return true;
  });

  ipcMain.handle("tracer:close", (_e, key: unknown, sha: unknown) => {
    const mr = findRequest(key, sha);
    if (!mr) return false;
    controller.close(mr);
    return true;
  });

  ipcMain.handle("tracer:openExternal", (_e, url: unknown) => {
    const target = typeof url === "string" ? browserURL(url) : null;
    if (target) void shell.openExternal(target);
  });

  ipcMain.handle("tracer:openNotificationSettings", () => {
    void shell.openExternal(
      isMac ? "x-apple.systempreferences:com.apple.Notifications-Settings.extension" : "ms-settings:notifications",
    );
  });

  ipcMain.handle("tracer:testNotification", async () => {
    // macOS suppresses banners for the frontmost app — drop the panel first.
    if (panel && !panel.isDestroyed() && panel.isVisible()) {
      panel.hide();
      await new Promise((r) => setTimeout(r, 400));
    }
    return notifier.preview();
  });

  ipcMain.handle("tracer:copy", (_e, text: unknown) => {
    if (typeof text === "string") clipboard.writeText(text);
  });

  ipcMain.handle("tracer:fit", (_e, width: unknown, height: unknown) => {
    if (typeof width === "number" && typeof height === "number" && Number.isFinite(width) && Number.isFinite(height)) {
      fitPanel(width, height);
    }
  });

  ipcMain.handle("tracer:hide", () => panel?.hide());
  ipcMain.handle("tracer:quit", () => app.quit());
}

async function boot(): Promise<void> {
  if (isMac) app.dock?.hide();
  store = new Store();
  controller = new Controller(store, broadcast);
  applyLoginItem(store.prefs);

  tray = new Tray(trayImage(false));
  tray.setToolTip("Pipeline Tracer");
  if (isMac) tray.setTitle("Pipeline Tracer");
  tray.on("click", () => togglePanel());
  tray.on("right-click", () => {
    const menu = Menu.buildFromTemplate([
      { label: "Open Pipeline Tracer", click: () => togglePanel() },
      { label: "Refresh now", click: () => void controller.refresh() },
      { type: "separator" },
      { label: "Quit Pipeline Tracer", click: () => app.quit() },
    ]);
    tray?.popUpContextMenu(menu);
  });

  wireIpc();
  panel = createPanel();

  await discoverPath();
  controller.schedule();
  void controller.refresh();
}

app.setName("Pipeline Tracer");
if (process.platform === "win32") app.setAppUserModelId(APP_ID);

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.whenReady().then(() => void boot());
  app.on("second-instance", () => togglePanel());
  app.on("before-quit", () => controller?.stop());
  // Tray app: stay alive with no windows.
  app.on("window-all-closed", () => {});
}
