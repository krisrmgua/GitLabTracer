import AppKit
import SwiftUI

/// Owns the menu bar item and its dropdown. Data is refreshed in the background; the menu
/// is rebuilt from the cached data each time it opens.
public final class MenuController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let inbox = InboxModel()
    private let popover = NSPopover()
    private let viewState = InboxViewState()
    private var reviewWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private var mergeRequests: [MergeRequest] = []
    private var cardPipeline: Pipeline?
    // What the last refresh saw, so only changes produce notifications.
    private var seenPipelineIDs = Set<String>()
    private var lastPipelineStatus: [String: String] = [:]
    private var lastJobStatus: [String: String] = [:]
    private var baselineDone = false
    /// Failures already announced, including ones found on the first refresh.
    private var notifiedFailureIDs: [String] = UserDefaults.standard.stringArray(forKey: "gitlabtracer.notifiedFailureIDs") ?? []
    private var pipelines: [Pipeline] = []
    private var lastGitLab: Date?
    private var gitlabTimer: Timer?
    private var gitlabRefreshing = false

    // Work runs one job at a time so git and merges never overlap.
    private let work = DispatchQueue(label: "gitlabtracer.work")
    private var pendingLabels: [String] = []
    private var lastResult: String?

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        popover.behavior = .transient
        popover.delegate = self
        // A menu-bar app often never becomes active, so a transient popover stays
        // up when you click another app. Close it the same way TokenPulse does.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, self.popover.isShown, let clicked = event.window,
               clicked !== self.popover.contentViewController?.view.window,
               clicked !== self.statusItem.button?.window,
               clicked.level.rawValue < NSWindow.Level.popUpMenu.rawValue, NSApp.modalWindow == nil {
                self.popover.performClose(nil)
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        popover.contentSize = NSSize(width: 430, height: 540)
        viewState.maximumHeight = min(700, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
        viewState.resize = { [weak self] size in
            guard let self else { return }
            self.popover.contentSize = size
            if let window = self.reviewWindow {
                let top = window.frame.maxY
                window.setContentSize(size)
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
            }
        }
        popover.contentViewController = NSHostingController(rootView: InboxView(model: inbox, state: viewState))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleInbox)
        inbox.merge = { [weak self] mr in self?.confirmMerge(mr) }
        inbox.close = { [weak self] mr in self?.confirmClose(mr) }
        inbox.refresh = { [weak self] in self?.scheduleTimers(); self?.refreshGitLab() }
        statusItem.button?.title = "Pipeline Tracer"
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    public func popoverDidClose(_ notification: Notification) {
        guard !PipelineTracerPrefs.rememberPlace else { return }
        viewState.returnToOverview()
    }

    @objc private func toggleInbox() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            Notifier.checkPermission { [weak self] in self?.inbox.notificationsEnabled = $0 }
            viewState.maximumHeight = min(700, (button.window?.screen?.visibleFrame.height ?? 800) - 40)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); refreshGitLab() }
    }

    public func start() {
        Notifier.requestAuthorization { [weak self] in self?.inbox.notificationsEnabled = $0 }
        refreshGitLab()
        scheduleTimers()
        if CommandLine.arguments.contains("--review-window") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Pipeline Tracer — Live review"
            window.contentView = NSHostingView(rootView: InboxView(model: inbox, state: viewState))
            reviewWindow = window
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.async { self.toggleInbox() } }
    }

    /// (Re)starts the GitLab refresh timer from the current setting.
    private func scheduleTimers() {
        gitlabTimer?.invalidate()
        gitlabTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(PipelineTracerPrefs.gitlabRefreshSeconds), repeats: true) { [weak self] _ in
            self?.refreshGitLab()
        }
    }

    // MARK: - Refresh

    public func menuWillOpen(_ menu: NSMenu) {
        rebuild()
        updateTitle()   // the ring and the card come from the same data, so they always agree
        if lastGitLab.map({ Date().timeIntervalSince($0) > 30 }) ?? true { refreshGitLab() }
    }

    func refreshGitLab() {
        guard !gitlabRefreshing else { return }
        gitlabRefreshing = true
        inbox.refreshing = true
        // Pipelines that were still going last time: reload jobs only when they finish,
        // so a failure notification can name the bad job without fetching every active pipe.
        let wasActive = Set(lastPipelineStatus.filter { Notifier.isActive($0.value) }.keys)
        let knownPipes = seenPipelineIDs
        let previousPipes = Dictionary(uniqueKeysWithValues: pipelines.map { ("\($0.projectID):\($0.id)", $0) })
        DispatchQueue.global(qos: .utility).async {
            guard GitLabModel.currentUser() != nil else {
                DispatchQueue.main.async {
                    self.gitlabRefreshing = false
                    self.inbox.refreshing = false
                    self.inbox.error = "Can’t reach GitLab. Check your connection and glab sign-in. Showing last received activity."
                }
                return
            }
            let failure = SnapshotFailure()
            let mrs = GitLabModel.fetchOpenMergeRequests(onFailure: { failure.mark() })
            var pipes = GitLabModel.fetchPipelines(hours: PipelineTracerPrefs.pipelineHours, onFailure: { failure.mark() })
            if failure.failed {
                DispatchQueue.main.async {
                    self.gitlabRefreshing = false; self.inbox.refreshing = false
                    self.inbox.error = "GitLab refresh incomplete. Showing last received activity; try Refresh again."
                }
                return
            }
            pipes = GitLabModel.annotateSourceBranches(pipes, openMRs: mrs)
            // Reuse jobs while status+sha are unchanged; only fetch the status-card pipe
            // and pipes that just left the active set (for failure detail).
            for i in pipes.indices {
                let key = "\(pipes[i].projectID):\(pipes[i].id)"
                if let old = previousPipes[key], old.status == pipes[i].status, old.sha == pipes[i].sha, !old.jobs.isEmpty {
                    pipes[i].jobs = old.jobs
                } else if let cached = GitLabModel.cachedJobs(projectID: pipes[i].projectID, pipelineID: pipes[i].id, status: pipes[i].status, sha: pipes[i].sha) {
                    pipes[i].jobs = cached
                }
            }
            let cardIndex = pipes.firstIndex(where: { $0.isRunning }) ?? (pipes.isEmpty ? nil : 0)
            if let i = cardIndex, pipes[i].jobs.isEmpty {
                if case .success(let jobs) = GitLabModel.jobsForPipeline(pipes[i]) { pipes[i].jobs = jobs }
            }
            for i in pipes.indices where pipes[i].jobs.isEmpty {
                let key = "\(pipes[i].projectID):\(pipes[i].id)"
                let leftActive = wasActive.contains(key) && !pipes[i].isRunning
                if leftActive || (pipes[i].isFailed && !knownPipes.contains(key)) {
                    if case .success(let jobs) = GitLabModel.jobsForPipeline(pipes[i]) { pipes[i].jobs = jobs }
                }
            }
            let card: Pipeline? = cardIndex.map { pipes[$0] }
            DispatchQueue.main.async {
                self.notifyMergeChanges(mrs)
                self.notifyChanges(pipes)
                self.mergeRequests = mrs
                self.pipelines = pipes
                self.cardPipeline = card
                self.lastGitLab = Date()
                self.gitlabRefreshing = false
                self.inbox.error = nil
                self.inbox.pipelines = pipes
                self.inbox.mrs = mrs
                self.inbox.updated = Date()
                self.inbox.refreshing = false
                self.updateTitle()
            }
        }
    }

    /// Compares this refresh with the last one and posts a notification for each change.
    /// Ordinary updates wait until the second refresh so launch is quiet.
    /// A failure notifies immediately, once, even if it was already waiting.
    private func notifyChanges(_ pipes: [Pipeline]) {
        if baselineDone {
            for p in pipes {
                let key = "\(p.projectID):\(p.id)"
                let before = lastPipelineStatus[key]
                let changed = !seenPipelineIDs.contains(key) || (before != nil && before != p.status)
                if changed && !p.isFailed {
                    let recovered = p.isSuccess &&
                        (before == "failed" || pipelines.contains { old in
                            old.projectID == p.projectID && old.isFailed && old.id != p.id &&
                            ((old.ref == p.ref && (p.updated ?? .distantPast) > (old.updated ?? .distantPast))
                             || (!old.sha.isEmpty && old.sha == p.sha && p.id > old.id))
                        })
                    let title = recovered ? "Pipeline recovered" : "Pipeline \(p.status.replacingOccurrences(of: "_", with: " "))"
                    publish(title, "\(p.project) #\(p.id) · \(p.ref)", status: p.status,
                            url: p.url, thread: key,
                            subtitle: "\(p.project) · #\(p.id)",
                            bannerBody: "Branch: \(p.ref)",
                            kind: .pipeline)
                }
                for j in p.jobs where j.status == "manual" {
                    guard let previous = lastJobStatus["\(p.projectID):\(j.id)"], previous != j.status else { continue }
                    publish("Action required",
                            "\(p.project) #\(p.id) · \(j.name): \(j.status) · \(p.ref)",
                            status: j.status, url: j.url, thread: key,
                            subtitle: "\(p.project) · #\(p.id)", bannerBody: "\(j.name) · \(p.ref)", kind: .logs)
                }
            }
        } else {
            baselineDone = true
        }
        announceFailures(pipes)
        record(pipes)
    }

    /// One banner per unresolved pipeline or failed job. Remembered across launches.
    private func announceFailures(_ pipes: [Pipeline]) {
        for p in GitLabModel.unresolvedFailures(pipes) {
            guard claimFailure("\(p.projectID):\(p.id)") else { continue }
            let failedJob = p.jobs.first { $0.status == "failed" }
            publish("Pipeline failed", "\(p.project) #\(p.id) · \(p.ref)", status: "failed",
                    url: failedJob?.url ?? p.url, thread: "\(p.projectID):\(p.id)",
                    subtitle: "\(p.project) · #\(p.id)",
                    bannerBody: failedJob.map { "\($0.name) failed · \(p.ref)" } ?? "Branch: \(p.ref)",
                    kind: failedJob == nil ? .pipeline : .logs)
            for j in p.jobs where j.status == "failed" {
                _ = claimFailure("\(p.projectID):job:\(j.id)")
            }
        }
        for p in pipes where !p.isFailed {
            for j in p.jobs where j.status == "failed" {
                guard claimFailure("\(p.projectID):job:\(j.id)") else { continue }
                publish("Job failed", "\(p.project) #\(p.id) · \(j.name): failed · \(p.ref)",
                        status: "failed", url: j.url, thread: "\(p.projectID):\(p.id)",
                        subtitle: "\(p.project) · #\(p.id)", bannerBody: "\(j.name) · \(p.ref)", kind: .logs)
            }
        }
    }

    private func claimFailure(_ key: String) -> Bool {
        guard !notifiedFailureIDs.contains(key) else { return false }
        notifiedFailureIDs.append(key)
        if notifiedFailureIDs.count > 300 { notifiedFailureIDs.removeFirst(notifiedFailureIDs.count - 300) }
        UserDefaults.standard.set(notifiedFailureIDs, forKey: "gitlabtracer.notifiedFailureIDs")
        return true
    }

    private func notifyMergeChanges(_ mrs: [MergeRequest]) {
        guard baselineDone else { return }
        for mr in mrs where mr.isReady {
            guard !mergeRequests.contains(where: { $0.key == mr.key && $0.isReady }) else { continue }
            publish("Ready to merge", "\(mr.project) !\(mr.iid) · \(mr.title)", status: "success",
                    url: mr.url, thread: "mr-\(mr.key)", subtitle: "\(mr.project) · !\(mr.iid)",
                    bannerBody: mr.title, kind: .readyMergeRequest)
        }
    }

    private func publish(_ title: String, _ detail: String, status: String, url: String, thread: String,
                         subtitle: String, bannerBody: String, kind: Notifier.Kind) {
        inbox.events.insert(ActivityEvent(title: title, detail: detail, status: status, url: url), at: 0)
        inbox.events = Array(inbox.events.prefix(60))
        Notifier.post(title, subtitle: subtitle, body: bannerBody, thread: thread,
                      important: status == "failed", url: url, kind: kind)
    }

    private func record(_ pipes: [Pipeline]) {
        for p in pipes {
            seenPipelineIDs.insert("\(p.projectID):\(p.id)")
            lastPipelineStatus["\(p.projectID):\(p.id)"] = p.status
            for j in p.jobs { lastJobStatus["\(p.projectID):\(j.id)"] = j.status }
        }
    }

    /// Menu bar text: merge requests, running and failed pipelines.
    func updateTitle() {
        let running = GitLabModel.groupSameChange(pipelines.filter { $0.isRunning }).count
        let failed = GitLabModel.groupSameChange(GitLabModel.unresolvedFailures(pipelines)).count
        let (status, progress) = PipelineProgressRing.state(for: cardPipeline)
        let button = statusItem.button
        button?.title = ""
        button?.image = MenuBarCapsule.image(mergeRequests: mergeRequests.count, running: running,
                                              failed: failed, status: status, progress: progress)
        button?.imagePosition = .imageOnly
        button?.setAccessibilityLabel("Pipeline Tracer: \(mergeRequests.count) merge requests, \(running) running pipelines, \(failed) failed pipelines")
        updateRing()
    }

    /// The progress ring for the pipeline the status card shows, with a tooltip describing it.
    private func updateRing() {
        guard let button = statusItem.button else { return }
        if let p = cardPipeline {
            let done = p.jobs.filter { ["success", "passed", "failed", "canceled", "cancelled", "skipped"].contains($0.status) }.count
            let jobLine = p.jobs.isEmpty ? "" : "\n\(done)/\(p.jobs.count) jobs finished"
            button.toolTip = "\(p.project) #\(p.id) · \(p.ref)\n\(p.status)\(jobLine)"
        } else {
            button.toolTip = "No recent pipelines"
        }
    }

    // MARK: - Menu

    private func rebuild() {
        menu.removeAllItems()
        let running = GitLabModel.groupSameChange(pipelines.filter { $0.isRunning }).count
        let failedNow = GitLabModel.unresolvedFailures(pipelines)
        let failed = GitLabModel.groupSameChange(failedNow).count
        let card = NSMenuItem()
        card.view = PipelineCard.view(for: cardPipeline,
                                      summary: "\(mergeRequests.count) MRs · \(running) running · \(failed) failed",
                                      openURL: { self.open($0) })
        menu.addItem(card)
        let runningNow = pipelines.filter { $0.isRunning }
        if !runningNow.isEmpty {
            addHeader("Running now")
            for p in runningNow { menu.addItem(pipelineItem(p)) }
        }
        if !failedNow.isEmpty {
            addHeader("Failed")
            for p in failedNow.prefix(20) { menu.addItem(pipelineItem(p)) }
        }
        menu.addItem(submenuItem("Merge requests (\(mergeRequests.count))", buildMergeRequests()))
        menu.addItem(submenuItem("Pipelines (\(pipelines.count))", buildPipelines()))

        menu.addItem(.separator())
        menu.addItem(submenuItem("Options", buildOptions()))
        if !pendingLabels.isEmpty {
            addHeader("Working: \(pendingLabels[0])" + (pendingLabels.count > 1 ? " (+\(pendingLabels.count - 1) queued)" : ""))
        }
        if let r = lastResult { addHeader(r) }
        menu.addItem(actionItem("Refresh now") { self.refreshGitLab() })
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Pipeline Tracer") { NSApp.terminate(nil) })
    }

    private func buildMergeRequests() -> NSMenu {
        let m = NSMenu()
        if mergeRequests.isEmpty { m.addItem(disabled("No open merge requests", .dim)) }
        for mr in mergeRequests {
            let sub = NSMenu()
            sub.addItem(disabled(mr.title, .plain))
            sub.addItem(disabled("Pipeline: \(mr.pipelineStatus ?? "none") · \(mr.isReady ? "ready" : mr.draft ? "draft" : mr.mergeStatus)", toneFor(pipeline: mr.pipelineStatus)))
            sub.addItem(.separator())
            sub.addItem(actionItem("Open in browser") { self.open(mr.url) })
            if mr.isReady && PipelineTracerPrefs.mergeButton {
                sub.addItem(actionItem("Merge…") { self.confirmMerge(mr) })
            }
            sub.addItem(actionItem("Close MR…") { self.confirmClose(mr) })
            let tone: Tone = mr.isReady ? .good : mr.draft ? .dim : toneFor(pipeline: mr.pipelineStatus)
            m.addItem(submenuItem("\(glyphForMR(mr)) \(mr.project) !\(mr.iid) — \(mr.title)", sub, tone: tone))
        }
        return m
    }

    private func buildPipelines() -> NSMenu {
        let m = NSMenu()
        if pipelines.isEmpty { m.addItem(disabled("No pipelines in the last 24h", .dim)) }
        let order: (Pipeline) -> Int = { $0.isRunning ? 0 : $0.isFailed ? 1 : 2 }
        let sorted = pipelines.sorted(by: { order($0) < order($1) })
        // Every running or failed pipeline, plus the 15 most recent of the rest.
        let shown = sorted.filter { $0.isRunning || $0.isFailed } + sorted.filter { !$0.isRunning && !$0.isFailed }.prefix(15)
        for p in shown { m.addItem(pipelineItem(p)) }
        return m
    }

    /// One pipeline as a dropdown row (with its stages and jobs in a submenu).
    private func pipelineItem(_ p: Pipeline) -> NSMenuItem {
        let (g, tone) = pipelineGlyph(p.status)
        return submenuItem("\(g) \(p.project) #\(p.id) · \(p.ref)", pipelineMenu(p), tone: tone)
    }

    private func pipelineMenu(_ p: Pipeline) -> NSMenu {
        let sub = NSMenu()
        sub.addItem(disabled("\(p.status) · \(p.ref)", pipelineGlyph(p.status).1))
        if !p.jobs.isEmpty {
            let done = p.jobs.filter { $0.status == "success" }.count
            let failed = p.jobs.filter { $0.status == "failed" }.count
            sub.addItem(disabled("Jobs: \(done)/\(p.jobs.count) passed" + (failed > 0 ? " · \(failed) failed" : ""), failed > 0 ? .bad : .plain))
            for stage in orderedStages(p.jobs) {
                let jobs = p.jobs.filter { $0.stage == stage }
                sub.addItem(.separator())
                // Stage row: the stage name, then one colored icon per job.
                let row = NSMutableAttributedString(attributedString: Palette.attributed("\(stage)   ", .plain))
                for j in jobs {
                    let (g, t) = jobGlyph(j.status)
                    row.append(Palette.attributed("\(g) ", t))
                }
                sub.addItem(attributedDisabled(row))
                for job in jobs {
                    let (g, t) = jobGlyph(job.status)
                    let dur = job.duration.map { " (\(formatDuration($0)))" } ?? ""
                    sub.addItem(actionItem("\(g) \(job.name)\(dur)", t) { self.open(job.url) })
                }
            }
            sub.addItem(.separator())
        }
        sub.addItem(actionItem("Open pipeline in browser") { self.open(p.url) })
        return sub
    }

    private func attributedDisabled(_ text: NSAttributedString) -> NSMenuItem {
        let item = NSMenuItem(title: text.string, action: nil, keyEquivalent: "")
        item.attributedTitle = text
        item.isEnabled = false
        return item
    }

    private func buildOptions() -> NSMenu {
        let m = NSMenu()
        let gl = NSMenu()
        gl.addItem(submenuItem("Refresh every", choiceMenu(
            PipelineTracerPrefs.gitlabRefreshChoices.map { ("\($0) seconds", $0) },
            current: PipelineTracerPrefs.gitlabRefreshSeconds) { PipelineTracerPrefs.gitlabRefreshSeconds = $0 }))
        gl.addItem(submenuItem("Finished pipelines shown for", choiceMenu(
            PipelineTracerPrefs.pipelineHourChoices.map { ($0 == 1 ? "1 hour" : "\($0) hours", $0) },
            current: PipelineTracerPrefs.pipelineHours) { PipelineTracerPrefs.pipelineHours = $0; self.refreshGitLab() }))
        gl.addItem(.separator())
        gl.addItem(toggleItem("Enable merge button", PipelineTracerPrefs.mergeButton) {
            PipelineTracerPrefs.mergeButton.toggle(); self.updateTitle()
        })
        m.addItem(submenuItem("GitLab", gl))
        return m
    }

    /// A radio-style list: the current value is checked, and choosing one applies it and reschedules.
    private func choiceMenu<T: Equatable>(_ options: [(String, T)], current: T, _ set: @escaping (T) -> Void) -> NSMenu {
        let m = NSMenu()
        for (label, value) in options {
            let item = actionItem(label) {
                set(value)
                self.scheduleTimers()
                self.updateTitle()
            }
            item.state = value == current ? .on : .off
            m.addItem(item)
        }
        return m
    }



    // MARK: - Actions

    private func confirmMerge(_ mr: MergeRequest) {
        guard inbox.merging == nil, inbox.closing == nil else { return }
        popover.performClose(nil)
        inbox.merging = mr.key
        enqueue("Merge !\(mr.iid)", successTitle: "Merge complete", failureTitle: "Merge failed", successStatus: "merged",
                completionURL: mr.url, completionDetail: mr.title, completionSubtitle: "\(mr.project) · !\(mr.iid)",
                refresh: { self.refreshGitLab() }) {
            switch GitLabModel.merge(mr) {
            case .merged: return nil
            case .failed(let msg): return msg
            }
        }
    }

    private func confirmClose(_ mr: MergeRequest) {
        guard inbox.merging == nil, inbox.closing == nil else { return }
        popover.performClose(nil)
        inbox.closing = mr.key
        enqueue("Close !\(mr.iid)", successTitle: "MR closed", failureTitle: "Close failed", successStatus: "canceled",
                completionURL: mr.url, completionDetail: mr.title, completionSubtitle: "\(mr.project) · !\(mr.iid)",
                refresh: { self.refreshGitLab() }) {
            switch GitLabModel.close(mr) {
            case .closed: return nil
            case .failed(let msg): return msg
            }
        }
    }

    /// Adds a job to the serial queue. `refresh` runs on the main thread after it finishes.
    private func enqueue(_ label: String, successTitle: String = "Merge complete", failureTitle: String = "Merge failed", successStatus: String = "merged", completionURL: String = "https://gitlab.com", completionDetail: String = "", completionSubtitle: String = "", refresh: @escaping () -> Void = {}, _ job: @escaping () -> String?) {
        DispatchQueue.main.async { self.pendingLabels.append(label) }
        work.async {
            let err = job()
            DispatchQueue.main.async {
                self.pendingLabels.removeAll { $0 == label }
                self.lastResult = err.map { "Failed: \(label) — \($0)" } ?? "Done: \(label)"
                self.inbox.result = self.lastResult
                self.inbox.merging = nil
                self.inbox.closing = nil
                self.publish(err == nil ? successTitle : failureTitle, completionSubtitle + " · " + (completionDetail.isEmpty ? label : completionDetail) + (err.map { " · " + $0 } ?? ""), status: err == nil ? successStatus : "failed", url: completionURL, thread: completionURL, subtitle: completionSubtitle, bannerBody: err ?? completionDetail, kind: .mergeRequest)
                refresh()
            }
        }
    }

    private func confirm(_ message: String, _ info: String, _ ok: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: - Menu item helpers

    private func addHeader(_ title: String) {
        menu.addItem(disabled(title, .dim))
    }

    /// Section title as a plain bold row. NSMenuItem.sectionHeader adds a lot of space above it,
    /// which left a gap under the status card.
    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func disabled(_ title: String, _ tone: Tone) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = Palette.attributed(title, tone)
        item.isEnabled = false
        return item
    }

    private func submenuItem(_ title: String, _ sub: NSMenu, tone: Tone = .plain) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = Palette.attributed(title, tone)
        item.submenu = sub
        return item
    }

    private func actionItem(_ title: String, _ tone: Tone = .plain, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.attributedTitle = Palette.attributed(title, tone)
        item.target = self
        item.representedObject = ActionBox(run)
        return item
    }

    private func toggleItem(_ title: String, _ on: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = actionItem(title, .plain, run)
        item.state = on ? .on : .off
        return item
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.run()
    }

    private final class ActionBox {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    /// Pipeline icon and color (same meaning as the iTerm toolbelt).
    private func pipelineGlyph(_ status: String) -> (String, Tone) {
        switch status {
        case "success", "passed": return ("✓", .good)
        case "failed": return ("✗", .bad)
        case "running": return ("●", .running)
        case "pending", "created", "preparing", "waiting_for_resource", "scheduled": return ("●", .warning)
        case "manual": return ("⏸", .caution)
        case "canceled", "cancelled": return ("⊘", .dim)
        case "skipped": return ("–", .dim)
        default: return ("○", .dim)
        }
    }

    private func jobGlyph(_ status: String) -> (String, Tone) {
        pipelineGlyph(status)
    }

    private func glyph(_ status: String) -> String {
        pipelineGlyph(status).0
    }

    private func toneFor(pipeline status: String?) -> Tone {
        pipelineGlyph(status ?? "").1
    }

    private func glyphForMR(_ mr: MergeRequest) -> String {
        mr.isReady ? "✓" : mr.draft ? "✎" : glyph(mr.pipelineStatus ?? "")
    }

    private func orderedStages(_ jobs: [Job]) -> [String] {
        var seen: [String] = []
        for j in jobs where !seen.contains(j.stage) { seen.append(j.stage) }
        return seen
    }

    private func formatDuration(_ s: Double) -> String {
        s < 60 ? "\(Int(s))s" : "\(Int(s) / 60)m\(String(format: "%02d", Int(s) % 60))s"
    }
}

private final class SnapshotFailure {
    private let lock = NSLock()
    private var value = false
    func mark() { lock.lock(); value = true; lock.unlock() }
    var failed: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
