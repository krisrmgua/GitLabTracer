import {
  cleanLog,
  DEFAULT_PREFS,
  descriptionSummary,
  formatDuration,
  groupSameChange,
  groupTitle,
  isDone,
  isFailed,
  isReady,
  isRunning,
  isSuccess,
  mergeRequestIID,
  mrKey,
  mrState,
  mrTone,
  numberLabel,
  pipelineKey,
  PIPELINE_HOUR_CHOICES,
  refLabel,
  REFRESH_CHOICES,
  relative,
  serviceName,
  statusTitle,
  unresolvedFailures,
  type ActivityEvent,
  type Job,
  type MergeRequest,
  type MrDetail,
  type Pipeline,
  type PipelineGroup,
  type Prefs,
  type TracerState,
} from "../../electron/logic";

interface TracerBridge {
  getState: () => Promise<TracerState>;
  refresh: () => Promise<void>;
  setPrefs: (prefs: Partial<Prefs>) => Promise<Prefs>;
  jobs: (pipelineKey: string, force: boolean) => Promise<Job[] | null>;
  log: (pipelineKey: string, job: Job) => Promise<string | null>;
  mrDetail: (key: string) => Promise<MrDetail | null>;
  merge: (key: string, sha: string) => Promise<boolean>;
  close: (key: string, sha: string) => Promise<boolean>;
  openExternal: (url: string) => Promise<void>;
  openNotificationSettings: () => Promise<void>;
  testNotification: () => Promise<void>;
  copy: (text: string) => Promise<void>;
  fit: (width: number, height: number) => Promise<void>;
  hide: () => Promise<void>;
  quit: () => Promise<void>;
  onState: (cb: (state: TracerState) => void) => () => void;
  onHidden: (cb: () => void) => () => void;
  onShown: (cb: () => void) => () => void;
}

declare global {
  interface Window {
    tracer: TracerBridge;
  }
}

const INBOX_WIDTH = 430;
const WORKSPACE_WIDTH = 620;
const WORKSPACE_HEIGHT = 540;

type View = "overview" | "settings" | "notifications" | "history" | "pipeline" | "mr";

let data: TracerState = {
  pipelines: [],
  mrs: [],
  events: [],
  refreshing: false,
  error: null,
  updated: null,
  result: null,
  merging: null,
  closing: null,
  prefs: { ...DEFAULT_PREFS },
  platform: "",
  cli: { glab: null, gh: null },
  notificationsSupported: true,
};

const ui = {
  view: "overview" as View,
  pipeline: null as Pipeline | null,
  group: [] as Pipeline[],
  groupJobs: new Map<number, Job[]>(),
  jobs: [] as Job[],
  loadingJobs: false,
  loadError: null as string | null,
  logJob: null as Job | null,
  logPipeline: null as Pipeline | null,
  logTab: "Logs" as "Logs" | "Summary",
  logText: "",
  loadingLog: false,
  search: "",
  mr: null as MergeRequest | null,
  mrDescription: "",
  mrAuthor: "",
  mrLoading: false,
  mrError: null as string | null,
  mrJobs: [] as Job[],
  confirming: null as null | "merge" | "close",
  expandedHistory: null as string | null,
  historyJobs: new Map<string, Job[]>(),
  historyLoading: null as string | null,
  historyError: null as string | null,
  showOther: false,
  eventFilter: "All" as "All" | "Pipelines" | "Merges",
  token: 0,
  logToken: 0,
};

function returnToOverview(): void {
  ui.token++;
  ui.logToken++;
  ui.view = "overview";
  ui.pipeline = null;
  ui.group = [];
  ui.groupJobs = new Map();
  ui.mr = null;
  ui.logJob = null;
  ui.logPipeline = null;
  ui.confirming = null;
  ui.loadError = null;
  ui.jobs = [];
  ui.loadingJobs = false;
}

// ---------------------------------------------------------------- rendering helpers

const $ = (id: string) => document.getElementById(id)!;

function esc(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

let actions: Array<() => void> = [];
let changes: Array<(value: string, checked: boolean) => void> = [];

/** Click handler attribute for the next render. Handlers are rebuilt on every render. */
function act(fn: () => void): string {
  actions.push(fn);
  return `data-act="${actions.length - 1}"`;
}

function onChange(fn: (value: string, checked: boolean) => void): string {
  changes.push(fn);
  return `data-chg="${changes.length - 1}"`;
}

const ICONS: Record<string, string> = {
  checkFill: `<circle cx="8" cy="8" r="7" fill="currentColor" stroke="none"/><path d="M4.8 8.2l2.1 2.1 4.3-4.5" stroke="#0e1a29" stroke-width="1.7"/>`,
  xFill: `<circle cx="8" cy="8" r="7" fill="currentColor" stroke="none"/><path d="M5.6 5.6l4.8 4.8M10.4 5.6l-4.8 4.8" stroke="#0e1a29" stroke-width="1.7"/>`,
  exclFill: `<circle cx="8" cy="8" r="7" fill="currentColor" stroke="none"/><path d="M8 4.4v4.4" stroke="#0e1a29" stroke-width="1.8"/><circle cx="8" cy="11.3" r="1" fill="#0e1a29" stroke="none"/>`,
  dotted: `<circle cx="8" cy="8" r="6.2" stroke-dasharray="2 2"/><circle cx="8" cy="8" r="2.4" fill="currentColor" stroke="none"/>`,
  pause: `<circle cx="8" cy="8" r="6.5"/><path d="M6.5 5.6v4.8M9.5 5.6v4.8"/>`,
  slash: `<circle cx="8" cy="8" r="6.5"/><path d="M4 12L12 4"/>`,
  minus: `<circle cx="8" cy="8" r="6.5"/><path d="M5 8h6"/>`,
  clock: `<circle cx="8" cy="8" r="6.5"/><path d="M8 4.6V8l2.3 1.6"/>`,
  branch: `<circle cx="4.5" cy="3.5" r="1.6"/><circle cx="4.5" cy="12.5" r="1.6"/><circle cx="11.5" cy="5" r="1.6"/><path d="M4.5 5.1v5.8M11.5 6.6c0 3-7 2.2-7 4.3"/>`,
  merge: `<circle cx="4.5" cy="3.5" r="1.6"/><circle cx="4.5" cy="12.5" r="1.6"/><circle cx="11.5" cy="10" r="1.6"/><path d="M4.5 5.1v5.8M4.5 5.1c0 3 3 4.9 5.4 4.9"/>`,
  pull: `<circle cx="4.5" cy="3.5" r="1.6"/><circle cx="4.5" cy="12.5" r="1.6"/><circle cx="11.5" cy="12.5" r="1.6"/><path d="M4.5 5.1v5.8M11.5 10.9V6a2 2 0 0 0-2-2H7.5M9 2.5L7.5 4 9 5.5"/>`,
  refresh: `<path d="M13 8a5 5 0 1 1-1.5-3.6M13 2.5v3h-3"/>`,
  bell: `<path d="M4 11V7.5a4 4 0 0 1 8 0V11l1 1.2H3L4 11z"/><path d="M6.8 13.6a1.3 1.3 0 0 0 2.4 0"/>`,
  gear: `<circle cx="8" cy="8" r="2.3"/><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4L5 11M11 5l1.4-1.4"/>`,
  chevL: `<path d="M10 3.5L5.5 8l4.5 4.5"/>`,
  chevR: `<path d="M6 3.5L10.5 8 6 12.5"/>`,
  chevD: `<path d="M3.5 6l4.5 4.5L12.5 6"/>`,
  chevU: `<path d="M3.5 10l4.5-4.5 4.5 4.5"/>`,
  ext: `<path d="M9 2.5h4.5V7M13.5 2.5L7.5 8.5"/><path d="M12 9.5v3.5H3V4h3.5"/>`,
  copy: `<rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/><path d="M10.5 3.5V3a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h.5"/>`,
  lock: `<rect x="3.5" y="7" width="9" height="7" rx="1.5" fill="currentColor"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/>`,
  warn: `<path d="M8 2l6.5 11.5h-13z"/><path d="M8 6.5v3.2"/><circle cx="8" cy="11.6" r=".6" fill="currentColor"/>`,
  closeCircle: `<circle cx="8" cy="8" r="6.5"/><path d="M5.8 5.8l4.4 4.4M10.2 5.8l-4.4 4.4"/>`,
};

function icon(name: string, color?: string, size = 14): string {
  const style = color ? ` style="color:${color}"` : "";
  return `<svg class="i" width="${size}" height="${size}" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"${style}>${ICONS[name] ?? ""}</svg>`;
}

function color(status: string): string {
  switch (status) {
    case "success":
    case "passed":
    case "merged":
    case "ready":
      return "var(--green)";
    case "failed":
      return "var(--red)";
    case "running":
      return "var(--orange)";
    case "manual":
    case "waiting_for_resource":
      return "var(--yellow)";
    default:
      return "var(--gray)";
  }
}

function statusIcon(status: string): string {
  switch (status) {
    case "success":
    case "passed":
    case "merged":
    case "ready":
      return "checkFill";
    case "failed":
      return "xFill";
    case "running":
      return "dotted";
    case "manual":
      return "pause";
    case "canceled":
    case "cancelled":
      return "slash";
    case "skipped":
      return "minus";
    default:
      return "clock";
  }
}

const tint = (c: string, pct: number) => `color-mix(in srgb, ${c} ${pct}%, transparent)`;

function badge(text: string, status: string): string {
  const c = color(status);
  return `<span class="badge" style="color:${c};background:${tint(c, 12)}">${icon(statusIcon(status), c, 11)}${esc(text)}</span>`;
}

function countLabel(n: number, c: string): string {
  return `<span class="count" style="color:${c};background:${tint(c, 10)}">${n}</span>`;
}

function heading(title: string, n: number, c: string, iconName: string): string {
  return `<div class="heading">${icon(iconName, c, 13)}<span>${esc(title)}</span>${countLabel(n, c)}</div>`;
}

function panel(items: string[]): string {
  return `<div class="panel">${items.join(`<div class="divider"></div>`)}</div>`;
}

const empty = (text: string) => `<div class="empty">${esc(text)}</div>`;
const flex = `<span style="flex:1"></span>`;
const completed = (jobs: Job[]) => jobs.filter((j) => isDone(j.status)).length;
const duration = (j: Job) => (j.duration != null ? formatDuration(j.duration) : null);

function open(url: string): void {
  void window.tracer.openExternal(url);
}

function ring(p: Pipeline): string {
  const done = completed(p.jobs);
  const progress = p.jobs.length ? done / p.jobs.length : isSuccess(p) ? 1 : 0;
  const c = color(p.status);
  const r = 11.5;
  const circ = 2 * Math.PI * r;
  const arc =
    progress > 0
      ? `<circle cx="13" cy="13" r="${r}" fill="none" stroke="${c}" stroke-width="3" stroke-linecap="round" stroke-dasharray="${(circ * progress).toFixed(2)} ${circ.toFixed(2)}"/>`
      : "";
  const label = p.jobs.length ? `<span class="label" style="color:${c}">${done}/${p.jobs.length}</span>` : icon(statusIcon(p.status), c, 10);
  const aria = p.jobs.length ? `${p.status}, ${done} of ${p.jobs.length} jobs finished` : `${p.status}, job details not loaded`;
  return `<span class="ring" aria-label="${esc(aria)}"><svg class="r" width="26" height="26" viewBox="0 0 26 26"><circle cx="13" cy="13" r="${r}" fill="none" stroke="${c}" stroke-opacity="0.22" stroke-width="3"/>${arc}</svg>${label}</span>`;
}

// ---------------------------------------------------------------- derived lists

const failureGroups = () => groupSameChange(unresolvedFailures(data.pipelines));
const activeGroups = () => groupSameChange(data.pipelines.filter((p) => isRunning(p) || p.status === "manual"));
const finished = () => data.pipelines.filter(isSuccess);
const otherCompletions = () => data.pipelines.filter((p) => ["canceled", "cancelled", "skipped"].includes(p.status));
const mergedEvents = () => data.events.filter((e) => e.status === "merged");

// ---------------------------------------------------------------- rows

function pipelineRow(p: Pipeline, expandHistory = false): string {
  const lead = isFailed(p) ? `<span class="fail-icon">${icon("exclFill", "var(--red)", 23)}</span>` : ring(p);
  const progress = isRunning(p)
    ? `<span class="progress-count mono">${p.jobs.length ? `${completed(p.jobs)}/${p.jobs.length}` : "—"}</span><span class="vrule"></span>`
    : "";
  const title = isFailed(p) ? "Pipeline failed" : p.workflow || `Pipeline #${p.id}`;
  const failedJob = isFailed(p) ? p.jobs.find((j) => j.status === "failed") : undefined;
  const tip = `${p.project} #${p.id} · ${refLabel(p)} · ${statusTitle(p.status)}`;
  return `<button class="row" title="${esc(tip)}" ${act(() => (expandHistory ? void toggleHistory(p) : void select(p)))}>
    ${lead}${progress}
    <span class="main">
      <span class="t">${esc(title)}</span>
      <span class="s">${esc(`${p.project} · ${refLabel(p)}`)}</span>
      ${failedJob ? `<span class="s">${esc(failedJob.name)} failed</span>` : ""}
    </span>
    <span class="when">${relative(p.updated)}</span>
    <span class="chev">${icon("chevR", undefined, 10)}</span>
  </button>`;
}

function groupRow(g: PipelineGroup): string {
  if (g.pipelines.length === 1) return pipelineRow(g.pipelines[0]);
  const branch = g.pipelines.find((p) => mergeRequestIID(p) == null);
  const mr = g.pipelines.find((p) => mergeRequestIID(p) != null);
  const iid = mr ? mergeRequestIID(mr) : 0;
  const when = Math.max(...g.pipelines.map((p) => p.updated ?? 0)) || null;
  const states = [mr ? `MR !${iid} · ${statusTitle(mr.status)}` : "", branch ? `branch · ${statusTitle(branch.status)}` : ""]
    .filter(Boolean)
    .join("&nbsp;&nbsp;");
  return `<button class="row" ${act(() => void selectGroup(g.pipelines))}>
    ${ring(g.primary)}
    <span class="main">
      <span class="t">${esc(groupTitle(g.pipelines))}</span>
      <span class="s">${esc(`${g.primary.project} · MR !${iid}`)}</span>
      <span class="s">${states}</span>
    </span>
    <span class="when">${relative(when)}</span>
    <span class="chev">${icon("chevR", undefined, 10)}</span>
  </button>`;
}

function mrRow(mr: MergeRequest): string {
  const c = color(mrTone(mr));
  return `<button class="row" title="${esc(`${numberLabel(mr)} ${mr.title} — ${mrState(mr)}`)}" ${act(() => void showMR(mr))}>
    <span style="width:22px;display:inline-flex;justify-content:center">${icon("branch", c, 19)}</span>
    <span class="main">
      <span class="t">${esc(`${numberLabel(mr)}  ${mr.title}`)}</span>
      <span class="s">${esc(mr.project)}</span>
    </span>
    <span class="when" style="color:${c}">${esc(mrState(mr))}</span>
    <span class="chev">${icon("chevR", undefined, 10)}</span>
  </button>`;
}

function jobRow(job: Job, onLogs: () => void, small = false): string {
  const c = color(job.status);
  return `<div class="jobrow${small ? " small" : ""}">
    ${icon(statusIcon(job.status), c, small ? 12 : 15)}
    <span class="name" title="${esc(job.name)}">${esc(job.name)}</span>
    <span class="dur">${esc(duration(job) ?? (small ? "—" : statusTitle(job.status)))}</span>
    <button class="inline" ${act(onLogs)}>View logs</button>
  </div>`;
}

// ---------------------------------------------------------------- views

function overview(): string {
  const parts: string[] = [];
  if (data.error) parts.push(`<div class="banner">${icon("warn", "var(--orange)", 13)}<span>${esc(data.error)}</span></div>`);
  if (data.result) parts.push(`<div class="note">${esc(data.result)}</div>`);
  const failures = failureGroups();
  if (failures.length) {
    parts.push(heading("Attention needed", failures.length, "var(--red)", "pull"));
    parts.push(panel(failures.map(groupRow)));
  }
  const active = activeGroups();
  const loading = data.refreshing && data.updated == null;
  parts.push(heading("Active", active.length, "var(--cyan)", "branch"));
  parts.push(panel(active.length ? active.map(groupRow) : [empty(loading ? "Loading pipelines…" : "No active pipelines")]));
  parts.push(heading("Requests", data.mrs.length, "var(--cyan)", "pull"));
  parts.push(panel(data.mrs.length ? data.mrs.map(mrRow) : [empty(loading ? "Loading requests…" : "No open requests")]));
  const recentCount = finished().length + mergedEvents().length;
  parts.push(
    panel([
      `<button class="row" style="padding:10px" ${act(() => {
        ui.view = "history";
        render();
      })}>${icon("checkFill", "var(--green)")}<span class="section-label">Recent successes</span>${countLabel(recentCount, "var(--green)")}${flex}${icon("chevD", undefined, 11)}</button>`,
    ]),
  );
  const other = otherCompletions();
  if (other.length) {
    const toggle = `<button class="row" style="padding:10px" ${act(() => {
      ui.showOther = !ui.showOther;
      render();
    })}><span class="section-label">Canceled &amp; skipped</span>${countLabel(other.length, "var(--muted)")}${flex}${icon(ui.showOther ? "chevU" : "chevD", undefined, 11)}</button>`;
    parts.push(panel(ui.showOther ? [toggle, ...other.map((p) => pipelineRow(p))] : [toggle]));
  }
  return `<div class="stack">${parts.join("")}</div>`;
}

function historyView(): string {
  const list = finished().slice(0, 30);
  const merged = mergedEvents();
  const items: string[] = [];
  for (const p of list) {
    const key = pipelineKey(p);
    let row = pipelineRow(p, true);
    if (ui.expandedHistory === key) {
      if (ui.historyLoading) row += `<div style="padding:8px"><span class="spinner"></span></div>`;
      if (ui.historyError) row += `<div class="note" style="color:var(--orange);padding:8px">${esc(ui.historyError)}</div>`;
      for (const job of ui.historyJobs.get(key) ?? p.jobs) {
        row += jobRow(
          job,
          () => {
            void select(p);
            void loadLog(job, p);
          },
          true,
        );
      }
    }
    items.push(row);
  }
  for (const ev of merged) {
    items.push(`<button class="row" style="padding:10px" ${act(() => open(ev.url))}>
      ${icon("merge", "var(--green)")}
      <span class="main"><span class="t" style="font-weight:500">${esc(ev.title)}</span><span class="s">${esc(ev.detail)}</span></span>
      <span class="tiny">${relative(ev.date)}</span>
    </button>`);
  }
  if (!items.length) items.push(empty("No recent completions"));
  return `<div class="stack wide">
    <div class="panel"><button class="row" style="padding:10px" ${act(() => {
      ui.view = "overview";
      render();
    })}>${icon("checkFill", "var(--green)")}<span class="section-label">Recent successes</span>${countLabel(list.length + merged.length, "var(--green)")}${flex}${icon("chevU", undefined, 11)}</button></div>
    <div class="tiny">${data.prefs.pipelineHours}-hour pipeline window · merge events from this session</div>
    ${panel(items)}
  </div>`;
}

function isMergeEvent(e: ActivityEvent): boolean {
  return e.url.includes("/merge_requests/") || e.url.includes("/pull/") || e.title.startsWith("Merge");
}

function eventProject(e: ActivityEvent): string {
  return e.detail.split(" ")[0] || "Pipeline Tracer";
}

function activateEvent(e: ActivityEvent): void {
  const p = data.pipelines.find((x) => x.url === e.url || x.jobs.some((j) => j.url === e.url));
  if (!p) {
    open(e.url);
    return;
  }
  void select(p);
  const failedJob = p.jobs.find((j) => j.status === "failed");
  if (e.status === "failed" && failedJob) void loadLog(failedJob, p);
}

function tabBar<T extends string>(items: Array<[T, string]>, current: T, set: (v: T) => void): string {
  return `<div class="tabs">${items
    .map(
      ([key, title]) =>
        `<button class="tab${key === current ? " active" : ""}" ${act(() => {
          set(key);
          render();
        })}>${esc(title)}</button>`,
    )
    .join("")}</div>`;
}

function notificationsView(): string {
  const events = data.events.filter((e) =>
    ui.eventFilter === "All" ? true : ui.eventFilter === "Merges" ? isMergeEvent(e) : !isMergeEvent(e),
  );
  const parts: string[] = [
    tabBar<"All" | "Pipelines" | "Merges">(
      [
        ["All", "All"],
        ["Pipelines", "Pipelines"],
        ["Merges", "Merges"],
      ],
      ui.eventFilter,
      (v) => (ui.eventFilter = v),
    ),
  ];
  if (!events.length) parts.push(empty("No notifications this session"));
  const projects = [...new Set(events.map(eventProject))];
  for (const project of projects) {
    parts.push(`<div class="note" style="font-weight:600">${esc(project)}</div>`);
    parts.push(
      panel(
        events
          .filter((e) => eventProject(e) === project)
          .map((e) => {
            const retry = e.title.toLowerCase().includes("connection");
            const label = retry
              ? "Retry"
              : e.url.includes("/merge_requests/")
                ? "View MR"
                : e.url.includes("/pull/")
                  ? "View PR"
                  : e.url.includes("/jobs/")
                    ? "View logs"
                    : "View pipeline";
            const c = color(e.status);
            return `<div class="event${e.status === "failed" ? " failed" : ""}">
              <span style="width:22px;display:inline-flex;justify-content:center">${icon(statusIcon(e.status), c)}</span>
              <span class="main" style="flex:1;min-width:0;display:flex;flex-direction:column;gap:4px">
                <span class="t">${esc(e.title)}</span>
                <span class="s">${esc(e.detail)}</span>
              </span>
              <span class="side">
                <span class="tiny">${relative(e.date)}</span>
                <button class="inline" ${act(() => (retry ? void window.tracer.refresh() : activateEvent(e)))}>${label}</button>
              </span>
            </div>`;
          }),
      ),
    );
  }
  parts.push(`<div class="tiny">This session · failures alert with sound; routine successes stay quiet</div>`);
  return `<div class="stack wide">${parts.join("")}</div>`;
}

function prefToggle(title: string, value: boolean, set: (v: boolean) => void): string {
  return `<label class="pref"><span class="label">${esc(title)}</span><input type="checkbox" class="switch" ${value ? "checked" : ""} ${onChange((_v, checked) => set(checked))} /></label>`;
}

function prefChoice(title: string, options: number[], value: number, suffix: (n: number) => string, set: (v: number) => void): string {
  const opts = options.map((o) => `<option value="${o}" ${o === value ? "selected" : ""}>${esc(suffix(o))}</option>`).join("");
  return `<div class="pref"><span class="label">${esc(title)}</span><select class="select" ${onChange((v) => set(Number(v)))}>${opts}</select></div>`;
}

const setPrefs = (p: Partial<Prefs>) => void window.tracer.setPrefs(p);

function cliRow(name: string, found: string | null): string {
  return `<div class="cli-row">
    <span style="width:34px;font-weight:600">${name}</span>
    ${found ? icon("checkFill", "var(--green)", 12) : icon("xFill", "var(--orange)", 12)}
    <span class="path mono">${esc(found ?? "Not found on PATH")}</span>
  </div>`;
}

function settingsView(): string {
  const prefs = data.prefs;
  const isWin = data.platform === "win32";
  const missing = !data.cli.glab || !data.cli.gh;
  const install = isWin ? "winget install glab.glab GitHub.cli" : "brew install glab gh";
  return `<div class="stack wide">
    <div class="section-label">Panel</div>
    ${panel([prefToggle("Reopen where I left off", prefs.rememberPlace, (v) => setPrefs({ rememberPlace: v }))])}
    <div class="section-label">Pipelines</div>
    ${panel([
      prefChoice("Refresh interval", REFRESH_CHOICES, prefs.refreshSeconds, (n) => `${n} seconds`, (v) => setPrefs({ refreshSeconds: v })),
      prefChoice("Completion history", PIPELINE_HOUR_CHOICES, prefs.pipelineHours, (n) => (n === 1 ? "1 hour" : `${n} hours`), (v) =>
        setPrefs({ pipelineHours: v }),
      ),
      prefToggle("Show merge actions", prefs.mergeButton, (v) => setPrefs({ mergeButton: v })),
    ])}
    ${isWin ? `<div class="section-label">System</div>${panel([prefToggle("Start at login", prefs.startAtLogin, (v) => setPrefs({ startAtLogin: v }))])}` : ""}
    <div class="section-label">Command-line tools</div>
    ${panel([
      cliRow("glab", data.cli.glab),
      cliRow("gh", data.cli.gh),
      `<div class="cli-row"><span class="note">${
        missing
          ? `Install with <span class="mono">${esc(install)}</span>, then <span class="mono">glab auth login --hostname gitlab.com</span> and <span class="mono">gh auth login --hostname github.com</span>. Either one is enough.`
          : "Tokens stay with glab and gh. Pipeline Tracer never stores them."
      }</span></div>`,
    ])}
    <div class="section-label">Notifications</div>
    ${panel([
      `<div class="stack" style="padding:10px">
        <div style="display:flex;gap:6px;align-items:center;color:var(--cyan)">${icon("bell", "var(--cyan)", 12)}<span>Failures alert · successes stay quiet</span></div>
        ${data.notificationsSupported ? "" : `<div class="note" style="color:var(--orange)">Notifications are not supported on this system.</div>`}
        <div class="note">Failures are titled Pipeline Tracer and play a sound. Click a banner to open its GitLab or GitHub page.</div>
        <div style="display:flex;gap:6px">
          <button class="inline" ${act(() => void window.tracer.openNotificationSettings())}>Notification settings</button>
          <button class="inline" ${data.notificationsSupported ? "" : "disabled"} ${act(() => void window.tracer.testNotification())}>Send test</button>
        </div>
      </div>`,
    ])}
    <div style="display:flex;justify-content:flex-end"><button class="inline" ${act(() => void window.tracer.quit())}>Quit Pipeline Tracer</button></div>
  </div>`;
}

function stageStatus(jobs: Job[], stage: string): string {
  const statuses = jobs.filter((j) => j.stage === stage).map((j) => j.status);
  if (statuses.includes("failed")) return "failed";
  if (statuses.includes("running")) return "running";
  if (statuses.includes("manual")) return "manual";
  if (statuses.every((s) => s === "success" || s === "passed")) return "success";
  if (statuses.every((s) => s === "skipped")) return "skipped";
  if (statuses.every((s) => s === "canceled" || s === "cancelled")) return "canceled";
  return "pending";
}

function stageTrack(jobs: Job[]): string {
  const stages = [...new Set(jobs.map((j) => j.stage))];
  const pieces = stages.map((stage, index) => {
    const list = jobs.filter((j) => j.stage === stage);
    const status = stageStatus(jobs, stage);
    const column = `<div class="stage">${icon(statusIcon(status), color(status), 24)}<span class="name">${esc(stage)}</span><span class="jobs">${completed(list)}/${list.length} jobs</span></div>`;
    return (index > 0 ? `<div class="link"></div>` : "") + column;
  });
  return `<div class="stage-track"><div class="inner">${pieces.join("")}</div></div>`;
}

function visibleLog(): string {
  if (!ui.search) return ui.logText;
  const needle = ui.search.toLowerCase();
  return ui.logText
    .split("\n")
    .filter((l) => l.toLowerCase().includes(needle))
    .join("\n");
}

function formattedLog(): string {
  return visibleLog()
    .split("\n")
    .map((line) => {
      const lower = line.toLowerCase();
      return lower.includes("error") || lower.includes("fail") ? `<span class="bad">${esc(line)}</span>` : esc(line);
    })
    .join("\n");
}

const logCount = () => `Log snapshot · latest 250,000 characters · ${visibleLog().split("\n").length} visible lines`;

function logView(p: Pipeline, job: Job): string {
  const c = color(job.status);
  const head = panel([
    `<div class="jobrow" style="padding:10px">${icon(statusIcon(job.status), c)}<span class="name" style="font-weight:600">${esc(job.name)}</span><span class="dur">${esc(duration(job) ?? "")}</span><button class="inline" ${act(() => {
      ui.logToken++;
      ui.logJob = null;
      ui.logPipeline = null;
      ui.loadError = null;
      ui.loadingLog = false;
      render();
    })}>All jobs</button></div>`,
  ]);
  const tabs = tabBar<"Logs" | "Summary">(
    [
      ["Logs", "Logs"],
      ["Summary", "Job summary"],
    ],
    ui.logTab,
    (v) => (ui.logTab = v),
  );
  if (ui.logTab === "Logs") {
    return `${head}${tabs}
      <div class="log-tools">
        <input id="log-search" class="search" placeholder="Search logs…" value="${esc(ui.search)}" />
        <button class="inline" ${ui.loadingLog || !ui.logText ? "disabled" : ""} ${act(() => void window.tracer.copy(ui.logText))}>${icon("copy", undefined, 11)}Copy</button>
        <button class="inline" ${act(() => open(job.url))}>${icon("ext", undefined, 11)}${serviceName(p)}</button>
      </div>
      ${ui.loadingLog ? `<div class="note"><span class="spinner"></span> Loading log…</div>` : ""}
      <pre class="log" id="log-pre">${formattedLog()}</pre>
      <div class="tiny" id="log-count">${logCount()}</div>`;
  }
  const meta = (k: string, v: string) => `<div class="meta"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`;
  return `${head}${tabs}
    ${panel([
      `<div class="stack wide" style="padding:12px">${meta("Job", job.name)}${meta("Stage", job.stage)}${meta("Status", statusTitle(job.status))}${meta("Duration", duration(job) ?? "Not reported")}</div>`,
    ])}
    <button class="action" ${act(() => open(job.url))}>Open job on ${serviceName(p)}</button>`;
}

function pipelineDetail(p: Pipeline): string {
  const parts: string[] = [
    `<div class="detail-head">
      <div class="main">
        <span class="t">${esc(`#${p.id}  ${p.project}`)}</span>
        <span class="s">${esc(`${refLabel(p)} · ${relative(p.updated)}`)}</span>
      </div>
      ${badge(statusTitle(p.status), p.status)}
      <button class="icon-btn" title="Open pipeline on ${serviceName(p)}" ${act(() => open(p.url))}>${icon("ext", "var(--cyan)")}</button>
    </div>`,
  ];
  if (ui.loadError) parts.push(`<div class="note" style="color:var(--orange)">${icon("warn", "var(--orange)", 11)} ${esc(ui.loadError)}</div>`);
  if (ui.logJob) {
    parts.push(logView(p, ui.logJob));
  } else {
    if (ui.loadingJobs) parts.push(`<div class="note"><span class="spinner"></span> Loading jobs…</div>`);
    if (ui.jobs.length) {
      parts.push(stageTrack(ui.jobs));
      parts.push(
        `<div style="display:flex"><span class="section-label" style="font-size:11px">Jobs (${ui.jobs.length})</span>${flex}<span class="note">${completed(ui.jobs)} finished</span></div>`,
      );
      parts.push(panel(ui.jobs.map((job) => jobRow(job, () => void loadLog(job, p)))));
    } else if (!ui.loadingJobs && !ui.loadError) {
      parts.push(empty(`No jobs available · Open ${serviceName(p)} for details`));
    }
  }
  return `<div class="stack wide">${parts.join("")}</div>`;
}

function groupDetail(pipelines: Pipeline[]): string {
  const parts: string[] = [
    `<div class="stack" style="gap:4px"><span class="t" style="font-size:13px;white-space:normal">${esc(groupTitle(pipelines))}</span><span class="s">${esc(pipelines[0].project)} · one change, two GitLab pipelines</span></div>`,
  ];
  if (ui.loadError) parts.push(`<div class="note" style="color:var(--orange)">${icon("warn", "var(--orange)", 11)} ${esc(ui.loadError)}</div>`);
  for (const p of pipelines) {
    const jobs = ui.groupJobs.get(p.id) ?? p.jobs;
    const iid = mergeRequestIID(p);
    parts.push(`<div class="stack" style="gap:8px">
      <div style="display:flex;align-items:center;gap:6px">
        <span class="section-label" style="font-size:11px">${iid == null ? "Branch" : `MR !${iid}`}</span>
        <span class="note mono">#${p.id}</span>${flex}
        ${badge(statusTitle(p.status), p.status)}
        <button class="icon-btn" ${act(() => open(p.url))}>${icon("ext", "var(--cyan)")}</button>
      </div>
      <div class="s">${esc(iid == null ? p.ref : `refs/merge-requests/${iid}/head`)}</div>
      ${ui.loadingJobs && !jobs.length ? `<div class="note"><span class="spinner"></span> Loading jobs…</div>` : ""}
      ${jobs.length ? panel(jobs.map((job) => jobRow(job, () => void loadLog(job, p)))) : ""}
    </div>`);
  }
  return `<div class="stack wide">${parts.join("")}</div>`;
}

function mrWorkspace(mr: MergeRequest): string {
  const list = data.mrs
    .map((item) => {
      const c = color(mrTone(item));
      return `<button class="mr-item${mrKey(item) === mrKey(mr) ? " selected" : ""}" ${act(() => void showMR(item))}>
        ${icon("branch", c)}
        <span class="main" style="flex:1;min-width:0;display:flex;flex-direction:column;gap:4px">
          <span class="t">${esc(`${numberLabel(item)}  ${item.title}`)}</span>
          <span class="tiny" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(item.project)}</span>
          <span class="tiny" style="color:${c}">${esc(mrState(item))}</span>
        </span>
      </button>`;
    })
    .join("");
  const isGitHub = mr.host === "github";
  const meta = (k: string, v: string) => `<div class="meta"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`;
  const pipeStatus = mr.pipelineStatus ?? "pending";
  const checks = panel([
    `<div class="jobrow" style="padding:10px">${icon(statusIcon(pipeStatus), color(pipeStatus))}<span class="name" style="font-weight:500">${isGitHub ? "Checks" : "Pipeline"}: ${esc(statusTitle(mr.pipelineStatus ?? "not reported"))}</span></div>`,
    ...ui.mrJobs.map(
      (job) =>
        `<div class="jobrow" style="padding:7px 10px;font-size:10px">${icon(statusIcon(job.status), color(job.status), 12)}<span class="name" style="font-size:10px">${esc(job.name)}</span><span class="dur">${esc(duration(job) ?? "—")}</span></div>`,
    ),
  ]);
  const busy = data.merging != null || data.closing != null;
  const ready = isReady(mr);
  const mergeDisabled = !ready || busy || ui.mrLoading || ui.mrError != null;
  const mergeButton = data.prefs.mergeButton
    ? `<button class="action primary" ${mergeDisabled ? "disabled" : ""} ${act(() => {
        ui.confirming = "merge";
        render();
      })}>${ready ? "" : icon("lock", undefined, 10)}${data.merging === mrKey(mr) ? "Merging…" : "Merge"}</button>`
    : "";
  const closeLabel = data.closing === mrKey(mr) ? "Closing…" : isGitHub ? "Close PR" : "Close MR";
  const closeButton = `<button class="action fit" ${busy || ui.mrLoading ? "disabled" : ""} ${act(() => {
    ui.confirming = "close";
    render();
  })}>${closeLabel}</button>`;
  const readyLine = data.prefs.mergeButton
    ? `<div class="note ${ready ? "ok-text" : "bad-text"}" style="font-weight:500">${ready ? "Ready to merge." : `Merge unavailable: ${esc(mrState(mr))}.`}</div>`
    : "";
  return `<div class="workspace-grid">
    <div class="list" data-scroll="mr-list">
      <div class="heading" style="padding-bottom:8px"><span>Requests</span>${countLabel(data.mrs.length, "var(--cyan)")}</div>
      ${list}
    </div>
    <div class="detail" data-scroll="mr-detail">
      <div class="stack wide">
        <div class="detail-head">
          ${icon("branch", "var(--cyan)")}
          <div class="main"><span class="t" style="font-size:13px">${esc(`${numberLabel(mr)}  ${mr.title}`)}</span><span class="s">${esc(mr.project)}</span></div>
          <button class="icon-btn" title="${isGitHub ? "Open pull request on GitHub" : "Open merge request in GitLab"}" ${act(() => open(mr.url))}>${icon("ext")}</button>
        </div>
        ${badge(mrState(mr), mrTone(mr))}
        ${ui.mrLoading ? `<div class="note"><span class="spinner"></span> Loading ${isGitHub ? "pull" : "merge"} request…</div>` : ""}
        ${ui.mrError ? `<div class="note" style="color:var(--orange)">${esc(ui.mrError)}</div>` : ""}
        ${ui.mrDescription ? `<div class="description">${esc(descriptionSummary(ui.mrDescription))}</div>` : ""}
        <div class="stack" style="gap:10px">
          ${meta("Source", mr.sourceBranch || "Not reported")}
          ${meta("Target", mr.targetBranch || "Not reported")}
          ${ui.mrAuthor ? meta("Author", ui.mrAuthor) : ""}
        </div>
        ${checks}
        <div style="display:flex;gap:8px">${mergeButton}${closeButton}</div>
        ${readyLine}
      </div>
    </div>
  </div>`;
}

function confirmation(mr: MergeRequest): string {
  const isGitHub = mr.host === "github";
  const cancel = `<button class="action" ${act(() => {
    ui.confirming = null;
    render();
  })}>Cancel</button>`;
  if (ui.confirming === "merge") {
    return `<div class="confirm" role="dialog" aria-modal="true">
      ${icon("merge", "var(--cyan)", 25)}
      <h2>${isGitHub ? "Merge pull request?" : "Merge request?"}</h2>
      <p>Merge ${esc(numberLabel(mr))} in ${esc(mr.project)}</p>
      <div class="sub mono">${esc(`${mr.sourceBranch} → ${mr.targetBranch}`)}</div>
      <div class="buttons">${cancel}<button class="action primary" id="confirm-ok" ${act(() => {
        ui.confirming = null;
        void window.tracer.merge(mrKey(mr), mr.sha);
        render();
      })}>Merge</button></div>
    </div>`;
  }
  return `<div class="confirm warn" role="dialog" aria-modal="true">
    ${icon("closeCircle", "var(--orange)", 25)}
    <h2>${isGitHub ? "Close pull request?" : "Close merge request?"}</h2>
    <p>Close ${esc(numberLabel(mr))} in ${esc(mr.project)}</p>
    <div class="sub">Leaves the source branch as-is. This does not delete anything.</div>
    <div class="buttons">${cancel}<button class="action primary" id="confirm-ok" ${act(() => {
      ui.confirming = null;
      void window.tracer.close(mrKey(mr), mr.sha);
      render();
    })}>${isGitHub ? "Close PR" : "Close MR"}</button></div>
  </div>`;
}

function screenTitle(): string {
  if (ui.logJob) return "Job logs";
  if (ui.view === "pipeline" && ui.group.length > 1) return groupTitle(ui.group);
  if (ui.view === "mr") return ui.mr?.host === "github" ? "Pull request" : "Merge request";
  if (ui.view === "pipeline") return "Pipeline";
  if (ui.view === "settings") return "Preferences";
  if (ui.view === "notifications") return "Notifications";
  if (ui.view === "history") return "Recent successes";
  return "Pipeline Tracer";
}

function header(): string {
  const title = screenTitle();
  const lead =
    ui.view === "overview"
      ? `<div class="title">${esc(title)}</div>`
      : `<button class="back" title="Back" ${act(() => {
          returnToOverview();
          render();
        })}>${icon("chevL", undefined, 12)}<span style="overflow:hidden;text-overflow:ellipsis">${esc(title)}</span></button>`;
  return `${lead}<div class="spacer"></div>
    ${data.refreshing ? `<span class="spinner"></span>` : ""}
    <button class="icon-btn" title="Refresh" ${act(() => void window.tracer.refresh())}>${icon("refresh")}</button>
    <button class="icon-btn" title="Notifications" ${act(() => {
      returnToOverview();
      ui.view = "notifications";
      render();
    })}>${icon("bell")}</button>
    <button class="icon-btn" title="Preferences" ${act(() => {
      returnToOverview();
      ui.view = "settings";
      render();
    })}>${icon("gear")}</button>`;
}

function footer(): string {
  const when = data.updated
    ? `Updated ${new Date(data.updated).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`
    : "Connecting…";
  return `<span>${esc(when)}</span><span>${data.mrs.length} MRs · ${activeGroups().length} active</span>`;
}

function body(): string {
  switch (ui.view) {
    case "settings":
      return settingsView();
    case "notifications":
      return notificationsView();
    case "history":
      return historyView();
    case "mr":
      return ui.mr ? mrWorkspace(ui.mr) : overview();
    case "pipeline":
      if (ui.logJob && ui.logPipeline) return pipelineDetail(ui.logPipeline);
      if (ui.group.length > 1) return groupDetail(ui.group);
      return ui.pipeline ? pipelineDetail(ui.pipeline) : overview();
    default:
      return overview();
  }
}

function render(): void {
  actions = [];
  changes = [];
  const focused = document.activeElement as HTMLInputElement | null;
  const focusId = focused?.id || null;
  const caret = focused && "selectionStart" in focused ? focused.selectionStart : null;
  const scrolls = new Map<string, number>();
  document.querySelectorAll<HTMLElement>("[data-scroll]").forEach((el) => scrolls.set(el.dataset.scroll!, el.scrollTop));
  const oldPre = document.getElementById("log-pre");

  $("top").innerHTML = header();
  const content = $("content");
  content.className = ui.view === "mr" && ui.mr ? "workspace" : "";
  content.innerHTML = body();
  $("foot").innerHTML = footer();

  // Keep the existing log node when its text is unchanged, so a background refresh does not
  // drop the reader's scroll position or text selection.
  const newPre = document.getElementById("log-pre");
  if (oldPre && newPre && oldPre.innerHTML === newPre.innerHTML) newPre.replaceWith(oldPre);

  const overlay = $("overlay");
  if (ui.confirming && ui.mr) {
    overlay.innerHTML = confirmation(ui.mr);
    overlay.classList.remove("hidden");
  } else {
    overlay.innerHTML = "";
    overlay.classList.add("hidden");
  }

  document.querySelectorAll<HTMLElement>("[data-scroll]").forEach((el) => {
    const top = scrolls.get(el.dataset.scroll!);
    if (top != null) el.scrollTop = top;
  });
  if (focusId) {
    const el = document.getElementById(focusId) as HTMLInputElement | null;
    if (el) {
      el.focus();
      if (caret != null && "setSelectionRange" in el) el.setSelectionRange(caret, caret);
    }
  }
  if (ui.confirming) document.getElementById("confirm-ok")?.focus();
  fit();
}

function fit(): void {
  requestAnimationFrame(() => {
    if (ui.view === "mr" && ui.mr) {
      void window.tracer.fit(WORKSPACE_WIDTH, WORKSPACE_HEIGHT);
      return;
    }
    const height = $("top").offsetHeight + $("content").getBoundingClientRect().height + $("foot").offsetHeight + 2;
    void window.tracer.fit(INBOX_WIDTH, Math.ceil(height));
  });
}

// ---------------------------------------------------------------- loaders

async function select(p: Pipeline): Promise<void> {
  returnToOverview();
  ui.view = "pipeline";
  ui.pipeline = p;
  ui.jobs = p.jobs;
  ui.loadingJobs = true;
  const token = ++ui.token;
  render();
  const jobs = await window.tracer.jobs(pipelineKey(p), false);
  if (token !== ui.token) return;
  ui.loadingJobs = false;
  if (jobs) ui.jobs = jobs;
  else ui.loadError = `Couldn’t load jobs. Check ${serviceName(p)} access or open in browser.`;
  render();
}

async function selectGroup(pipelines: Pipeline[]): Promise<void> {
  returnToOverview();
  ui.view = "pipeline";
  ui.group = pipelines;
  ui.pipeline = pipelines[0];
  for (const p of pipelines) ui.groupJobs.set(p.id, p.jobs);
  ui.loadingJobs = true;
  const token = ++ui.token;
  render();
  const results = await Promise.all(pipelines.map((p) => window.tracer.jobs(pipelineKey(p), false)));
  if (token !== ui.token) return;
  ui.loadingJobs = false;
  let loaded = 0;
  results.forEach((jobs, i) => {
    if (!jobs) return;
    ui.groupJobs.set(pipelines[i].id, jobs);
    loaded++;
  });
  if (loaded !== pipelines.length) ui.loadError = "Couldn’t load every pipeline. Open the missing one in the browser.";
  render();
}

async function toggleHistory(p: Pipeline): Promise<void> {
  const key = pipelineKey(p);
  if (ui.expandedHistory === key) {
    ui.expandedHistory = null;
    render();
    return;
  }
  ui.expandedHistory = key;
  ui.historyError = null;
  ui.historyLoading = key;
  render();
  const jobs = await window.tracer.jobs(key, false);
  if (ui.expandedHistory !== key) return;
  ui.historyLoading = null;
  if (jobs) ui.historyJobs.set(key, jobs);
  else ui.historyError = `Couldn’t load completed jobs. Open the pipeline in ${serviceName(p)}.`;
  render();
}

async function loadLog(job: Job, p: Pipeline): Promise<void> {
  ui.logJob = job;
  ui.logPipeline = p;
  ui.logTab = "Logs";
  ui.search = "";
  ui.logText = "";
  ui.loadingLog = true;
  ui.loadError = null;
  const token = ++ui.logToken;
  render();
  const text = await window.tracer.log(pipelineKey(p), job);
  if (token !== ui.logToken) return;
  ui.loadingLog = false;
  if (text == null) ui.loadError = `Couldn’t load log. Open this job on ${serviceName(p)}.`;
  else ui.logText = cleanLog(text) || "No log output yet.";
  render();
}

async function showMR(mr: MergeRequest): Promise<void> {
  ui.view = "mr";
  ui.mr = mr;
  ui.confirming = null;
  ui.mrError = null;
  ui.mrJobs = [];
  ui.mrDescription = "";
  ui.mrAuthor = "";
  ui.mrLoading = true;
  const token = ++ui.token;
  render();
  const detail = await window.tracer.mrDetail(mrKey(mr));
  if (token !== ui.token) return;
  ui.mrLoading = false;
  if (detail) {
    ui.mr = detail.request;
    ui.mrDescription = detail.body;
    ui.mrAuthor = detail.author;
    ui.mrJobs = detail.jobs;
  } else {
    ui.mrError =
      mr.host === "github"
        ? "Couldn’t refresh pull request details. Open GitHub or try again."
        : "Couldn’t refresh merge details. Open GitLab or try again.";
  }
  render();
}

// ---------------------------------------------------------------- wiring

function applyState(next: TracerState): void {
  data = next;
  const current = ui.mr;
  if (ui.view === "mr" && current && !ui.mrLoading && !ui.confirming) {
    const fresh = data.mrs.find((m) => mrKey(m) === mrKey(current));
    if (!fresh) {
      const kind = current.host === "github" ? "pull request" : "merge request";
      ui.mrError = `This ${kind} is no longer in the open list. Refresh or open ${current.host === "github" ? "GitHub" : "GitLab"}.`;
    } else {
      ui.mr = fresh.pipelineStatus == null ? { ...fresh, pipelineStatus: current.pipelineStatus } : fresh;
    }
  }
  render();
}

document.addEventListener("click", (e) => {
  const el = (e.target as Element | null)?.closest<HTMLElement>("[data-act]");
  if (!el || (el as HTMLButtonElement).disabled) return;
  if (el.closest("#overlay") == null && ui.confirming) return;
  actions[Number(el.dataset.act)]?.();
});

document.addEventListener("change", (e) => {
  const el = e.target as HTMLInputElement | HTMLSelectElement | null;
  if (!el?.dataset.chg) return;
  changes[Number(el.dataset.chg)]?.(el.value, (el as HTMLInputElement).checked);
});

document.addEventListener("input", (e) => {
  const el = e.target as HTMLInputElement | null;
  if (el?.id !== "log-search") return;
  ui.search = el.value;
  const pre = document.getElementById("log-pre");
  if (pre) pre.innerHTML = formattedLog();
  const count = document.getElementById("log-count");
  if (count) count.textContent = logCount();
});

$("overlay").addEventListener("click", (e) => {
  if (e.target === e.currentTarget) {
    ui.confirming = null;
    render();
  }
});

document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  if (ui.confirming) ui.confirming = null;
  else if (ui.view !== "overview") returnToOverview();
  else {
    void window.tracer.hide();
    return;
  }
  render();
});

window.tracer.onState(applyState);
window.tracer.onHidden(() => {
  ui.confirming = null;
  if (!data.prefs.rememberPlace) returnToOverview();
  render();
});
window.tracer.onShown(() => fit());
// Relative times ("3m ago") stay current while the panel is open.
setInterval(() => {
  if (document.visibilityState === "visible" && ["overview", "history", "notifications"].includes(ui.view)) render();
}, 30_000);

void window.tracer.getState().then(applyState);
