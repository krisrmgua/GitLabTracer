import { randomUUID } from "node:crypto";
import { app } from "electron";
import {
  isActiveStatus,
  isFailed,
  isReady,
  isRunning,
  settlePipeline,
  isSuccess,
  mrKey,
  numberLabel,
  pipelineKey,
  refLabel,
  unresolvedFailures,
  type ActivityEvent,
  type MergeRequest,
  type NotificationKind,
  type Pipeline,
  type Prefs,
  type TracerState,
} from "./logic";
import * as model from "./model";
import * as notifier from "./notifier";
import { refreshToolsIfMissing, toolPath } from "./shell";
import type { Store } from "./store";

/**
 * Owns the refresh timer, the last snapshot, and the change detection that drives
 * notifications. A port of the Swift MenuController without the AppKit parts.
 */
export class Controller {
  pipelines: Pipeline[] = [];
  mrs: MergeRequest[] = [];
  cardPipeline: Pipeline | null = null;
  private events: ActivityEvent[] = [];
  private refreshing = false;
  private error: string | null = null;
  private updated: number | null = null;
  private result: string | null = null;
  private merging: string | null = null;
  private closing: string | null = null;

  // What the last refresh saw, so only changes produce notifications.
  private seenPipelineIDs = new Set<string>();
  private lastPipelineStatus = new Map<string, string>();
  private lastJobStatus = new Map<string, string>();
  private baselineDone = false;

  private timer: NodeJS.Timeout | null = null;
  /** Merges and closes run one at a time. */
  private work: Promise<void> = Promise.resolve();

  constructor(
    private store: Store,
    private onChange: () => void,
  ) {}

  snapshot(): TracerState {
    return {
      pipelines: this.pipelines,
      mrs: this.mrs,
      events: this.events,
      refreshing: this.refreshing,
      error: this.error,
      updated: this.updated,
      result: this.result,
      merging: this.merging,
      closing: this.closing,
      prefs: this.store.prefs,
      platform: process.platform,
      version: app.getVersion(),
      cli: { glab: toolPath("glab"), gh: toolPath("gh") },
      notificationsSupported: notifier.notificationsSupported(),
    };
  }

  /** (Re)starts the refresh timer from the current setting. */
  schedule(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = setInterval(() => void this.refresh(), this.store.prefs.refreshSeconds * 1000);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  prefsChanged(before: Prefs, after: Prefs): void {
    if (before.refreshSeconds !== after.refreshSeconds) this.schedule();
    if (before.refreshSeconds !== after.refreshSeconds || before.pipelineHours !== after.pipelineHours) {
      void this.refresh();
    }
    this.onChange();
  }

  async refresh(): Promise<void> {
    if (this.refreshing) return;
    this.refreshing = true;
    this.onChange();
    try {
      await this.doRefresh();
    } finally {
      this.refreshing = false;
      this.onChange();
    }
  }

  private async doRefresh(): Promise<void> {
    await refreshToolsIfMissing();
    const hours = this.store.prefs.pipelineHours;
    // Pipelines still going last time: reload jobs only when they finish, so a failure
    // notification can name the bad job without fetching every active pipeline.
    const wasActive = new Set([...this.lastPipelineStatus].filter(([, s]) => isActiveStatus(s)).map(([k]) => k));
    const knownPipes = new Set(this.seenPipelineIDs);
    const previousPipes = new Map(this.pipelines.map((p) => [pipelineKey(p), p]));
    const previousGitLab = this.pipelines.filter((p) => p.host === "gitlab");
    const previousGitHub = this.pipelines.filter((p) => p.host === "github");
    const previousGitLabMRs = this.mrs.filter((m) => m.host === "gitlab");
    const previousGitHubMRs = this.mrs.filter((m) => m.host === "github");

    const glab = toolPath("glab");
    const gh = toolPath("gh");
    if (!glab && !gh) {
      this.error = "Couldn’t find glab or gh. Install one, sign in, then press Refresh. Preferences lists where Tracer looked.";
      return;
    }

    const [gitlabUser, githubUser] = await Promise.all([
      glab ? model.currentUser() : Promise.resolve(null),
      gh ? model.githubLogin() : Promise.resolve(null),
    ]);
    if (!gitlabUser && !githubUser) {
      this.error = "Can’t reach GitLab or GitHub. Check your connection and glab or gh sign-in. Showing last received activity.";
      return;
    }

    let gitlabFailedFlag = false;
    const markFailed = () => {
      gitlabFailedFlag = true;
    };
    const gitlabWork = gitlabUser
      ? Promise.all([model.fetchOpenMergeRequests(markFailed), model.fetchPipelines(hours, markFailed)])
      : Promise.resolve([[], []] as [MergeRequest[], Pipeline[]]);
    const githubWork = githubUser
      ? Promise.all([model.fetchGitHubPipelines(hours), model.fetchOpenPullRequests()])
      : Promise.resolve([null, null] as [Pipeline[] | null, MergeRequest[] | null]);
    const [[glMRs, glPipes], [ghPipes, ghPulls]] = await Promise.all([gitlabWork, githubWork]);

    let mrs = glMRs;
    let gitlabPipes = glPipes;
    const gitlabOK = gitlabUser != null && !gitlabFailedFlag;
    if (gitlabOK) gitlabPipes = await model.annotateSourceBranches(gitlabPipes, mrs);

    let githubPipes = ghPipes ?? [];
    const githubOK = ghPipes != null;
    let githubMRs = ghPulls ?? [];
    const pullsOK = githubUser ? ghPulls != null : previousGitHubMRs.length === 0;

    const gitlabFailed =
      (gitlabUser != null && !gitlabOK) || (gitlabUser == null && (previousGitLab.length > 0 || previousGitLabMRs.length > 0));
    const githubFailed = (githubUser != null && !githubOK) || (githubUser == null && previousGitHub.length > 0);
    if (gitlabFailed && githubFailed && !pullsOK) {
      this.error = "Refresh incomplete. Showing last received activity; try Refresh again.";
      return;
    }
    if (gitlabFailed) {
      gitlabPipes = previousGitLab;
      mrs = previousGitLabMRs;
    }
    if (githubFailed) githubPipes = previousGitHub;
    if (!pullsOK) githubMRs = previousGitHubMRs;
    mrs = [...mrs, ...githubMRs].sort((a, b) => (b.updated ?? 0) - (a.updated ?? 0));
    const pipes = [...gitlabPipes, ...githubPipes].sort((a, b) => (b.updated ?? 0) - (a.updated ?? 0));

    const notes: string[] = [];
    if (gitlabFailed) notes.push("GitLab refresh incomplete. Showing the last GitLab activity.");
    if (githubFailed) notes.push("GitHub Actions refresh incomplete. Showing the last GitHub activity.");
    if (!pullsOK && (githubUser != null || previousGitHubMRs.length > 0)) {
      notes.push("GitHub pull requests refresh incomplete. Showing the last pull requests.");
    }

    // Reuse jobs while status+sha are unchanged. A live pipeline is the exception:
    // its jobs move while the list still says "running".
    for (let i = 0; i < pipes.length; i++) {
      if (isRunning(pipes[i])) continue;
      const old = previousPipes.get(pipelineKey(pipes[i]));
      if (old && old.status === pipes[i].status && old.sha === pipes[i].sha && old.jobs.length) {
        pipes[i] = { ...pipes[i], jobs: old.jobs };
      } else {
        const cached = model.cachedJobs(pipes[i]);
        if (cached) pipes[i] = { ...pipes[i], jobs: cached };
      }
    }
    // Fetch jobs for live pipelines, the status card, and pipelines that just finished or newly failed.
    const runningIndex = pipes.findIndex(isRunning);
    const cardIndex = runningIndex >= 0 ? runningIndex : pipes.length ? 0 : -1;
    const toLoad = new Set<number>();
    if (cardIndex >= 0 && !pipes[cardIndex].jobs.length) toLoad.add(cardIndex);
    pipes.forEach((p, i) => {
      if (isRunning(p)) {
        toLoad.add(i);
        return;
      }
      if (p.jobs.length) return;
      const key = pipelineKey(p);
      const leftActive = wasActive.has(key) && !isRunning(p);
      if (leftActive || (isFailed(p) && !knownPipes.has(key))) toLoad.add(i);
    });
    await Promise.all(
      [...toLoad].map(async (i) => {
        const jobs = await model.jobsForPipeline(pipes[i], isRunning(pipes[i]));
        if (jobs) pipes[i] = settlePipeline({ ...pipes[i], jobs });
      }),
    );

    this.notifyMergeChanges(mrs);
    this.notifyChanges(pipes);
    this.mrs = mrs;
    this.pipelines = pipes;
    this.cardPipeline = cardIndex >= 0 ? pipes[cardIndex] : null;
    this.error = notes.length ? notes.join(" ") : null;
    this.updated = Date.now();
  }

  /**
   * Compares this refresh with the last one and posts a notification for each change.
   * Ordinary updates wait until the second refresh so launch is quiet. A failure notifies
   * immediately, once, even if it was already waiting.
   */
  private notifyChanges(pipes: Pipeline[]): void {
    if (this.baselineDone) {
      for (const p of pipes) {
        const key = pipelineKey(p);
        const before = this.lastPipelineStatus.get(key);
        const changed = !this.seenPipelineIDs.has(key) || (before != null && before !== p.status);
        if (changed && !isFailed(p)) {
          const recovered =
            isSuccess(p) &&
            (before === "failed" ||
              this.pipelines.some(
                (old) =>
                  old.host === p.host &&
                  old.projectID === p.projectID &&
                  isFailed(old) &&
                  old.id !== p.id &&
                  (p.host !== "github" || old.workflow === p.workflow) &&
                  ((old.ref === p.ref && (p.updated ?? 0) > (old.updated ?? 0)) ||
                    (old.sha !== "" && old.sha === p.sha && p.id > old.id)),
              ));
          const title = recovered ? "Pipeline recovered" : `Pipeline ${p.status.replaceAll("_", " ")}`;
          this.publish(title, `${p.project} #${p.id} · ${refLabel(p)}`, p.status, p.url, key, `${p.project} · #${p.id}`, `Branch: ${refLabel(p)}`, "pipeline");
        }
        for (const j of p.jobs) {
          if (j.status !== "manual") continue;
          const previous = this.lastJobStatus.get(`${key}:${j.id}`);
          if (previous == null || previous === j.status) continue;
          this.publish(
            "Action required",
            `${p.project} #${p.id} · ${j.name}: ${j.status} · ${p.ref}`,
            j.status,
            j.url,
            key,
            `${p.project} · #${p.id}`,
            `${j.name} · ${p.ref}`,
            "logs",
          );
        }
      }
    } else {
      this.baselineDone = true;
    }
    this.announceFailures(pipes);
    for (const p of pipes) {
      const key = pipelineKey(p);
      this.seenPipelineIDs.add(key);
      this.lastPipelineStatus.set(key, p.status);
      for (const j of p.jobs) this.lastJobStatus.set(`${key}:${j.id}`, j.status);
    }
  }

  /** One banner per unresolved pipeline or failed job. Remembered across launches. */
  private announceFailures(pipes: Pipeline[]): void {
    for (const p of unresolvedFailures(pipes)) {
      const key = pipelineKey(p);
      if (!this.store.claimFailure(key)) continue;
      const failedJob = p.jobs.find((j) => j.status === "failed");
      this.publish(
        "Pipeline failed",
        `${p.project} #${p.id} · ${refLabel(p)}`,
        "failed",
        failedJob?.url || p.url,
        key,
        `${p.project} · #${p.id}`,
        failedJob ? `${failedJob.name} failed · ${refLabel(p)}` : `Branch: ${refLabel(p)}`,
        failedJob ? "logs" : "pipeline",
      );
      for (const j of p.jobs) if (j.status === "failed") this.store.claimFailure(`${key}:job:${j.id}`);
    }
    for (const p of pipes) {
      if (isFailed(p)) continue;
      const key = pipelineKey(p);
      for (const j of p.jobs) {
        if (j.status !== "failed" || !this.store.claimFailure(`${key}:job:${j.id}`)) continue;
        this.publish(
          "Job failed",
          `${p.project} #${p.id} · ${j.name}: failed · ${p.ref}`,
          "failed",
          j.url,
          `${p.projectID}:${p.id}`,
          `${p.project} · #${p.id}`,
          `${j.name} · ${p.ref}`,
          "logs",
        );
      }
    }
  }

  private notifyMergeChanges(mrs: MergeRequest[]): void {
    if (!this.baselineDone) return;
    for (const mr of mrs) {
      if (!isReady(mr)) continue;
      if (this.mrs.some((old) => mrKey(old) === mrKey(mr) && isReady(old))) continue;
      this.publish(
        "Ready to merge",
        `${mr.project} ${numberLabel(mr)} · ${mr.title}`,
        "success",
        mr.url,
        `mr-${mrKey(mr)}`,
        `${mr.project} · ${numberLabel(mr)}`,
        mr.title,
        "readyMergeRequest",
      );
    }
  }

  private publish(
    title: string,
    detail: string,
    status: string,
    url: string,
    thread: string,
    subtitle: string,
    bannerBody: string,
    kind: NotificationKind,
  ): void {
    this.events = [{ id: randomUUID(), title, detail, status, url, date: Date.now() }, ...this.events].slice(0, 60);
    notifier.post(title, subtitle, bannerBody, thread, status === "failed", url, kind);
  }

  merge(mr: MergeRequest): void {
    if (this.merging || this.closing) return;
    this.merging = mrKey(mr);
    this.onChange();
    this.enqueue(`Merge ${numberLabel(mr)}`, "Merge complete", "Merge failed", "merged", mr, () => model.merge(mr));
  }

  close(mr: MergeRequest): void {
    if (this.merging || this.closing) return;
    this.closing = mrKey(mr);
    this.onChange();
    this.enqueue(
      `Close ${numberLabel(mr)}`,
      mr.host === "github" ? "PR closed" : "MR closed",
      "Close failed",
      "canceled",
      mr,
      () => model.close(mr),
    );
  }

  private enqueue(
    label: string,
    successTitle: string,
    failureTitle: string,
    successStatus: string,
    mr: MergeRequest,
    job: () => Promise<model.Outcome>,
  ): void {
    this.work = this.work.then(async () => {
      let outcome: model.Outcome;
      try {
        outcome = await job();
      } catch (err) {
        outcome = { ok: false, message: err instanceof Error ? err.message : String(err) };
      }
      const err = outcome.ok ? null : outcome.message;
      this.result = err ? `Failed: ${label} — ${err}` : `Done: ${label}`;
      this.merging = null;
      this.closing = null;
      const subtitle = `${mr.project} · ${numberLabel(mr)}`;
      this.publish(
        err ? failureTitle : successTitle,
        `${subtitle} · ${mr.title}${err ? ` · ${err}` : ""}`,
        err ? "failed" : successStatus,
        mr.url,
        mr.url,
        subtitle,
        err ?? mr.title,
        "mergeRequest",
      );
      this.onChange();
      await this.refresh();
    });
  }
}
