import AppKit
import SwiftUI

struct ActivityEvent: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let status: String
    let url: String
    let date = Date()
}

final class InboxModel: ObservableObject {
    @Published var events: [ActivityEvent] = []
    @Published var pipelines: [Pipeline] = []
    @Published var mrs: [MergeRequest] = []
    @Published var refreshing = false
    @Published var notificationsEnabled: Bool?
    @Published var error: String?
    @Published var updated: Date?
    @Published var result: String?
    @Published var merging: String?
    @Published var closing: String?
    var preview = false
    var merge: (MergeRequest) -> Void = { _ in }
    var close: (MergeRequest) -> Void = { _ in }
    var refresh: () -> Void = {}
}

private enum Deck {
    static let background = Color(red: 0.055, green: 0.10, blue: 0.16)
    static let card = Color(red: 0.10, green: 0.17, blue: 0.25)
    static let cyan = Color(red: 0.30, green: 0.82, blue: 0.96)
    static func color(_ status: String) -> Color {
        switch status {
        case "success", "passed", "merged", "ready": return .green
        case "failed": return .red
        case "running": return .orange
        case "manual", "waiting_for_resource": return .yellow
        default: return .gray
        }
    }
    static func title(_ status: String) -> String {
        switch status {
        case "success", "passed": return "Passed"
        case "ci_still_running": return "Checks running"
        case "ci_must_pass": return "Checks required"
        case "unchecked", "checking": return "Checking readiness"
        case "waiting_for_resource": return "Waiting for resource"
        case "manual": return "Action required"
        case "created", "pending", "preparing", "scheduled": return "Queued"
        case "draft_status": return "Draft"
        case "not_approved": return "Approval needed"
        case "conflict": return "Merge conflict"
        case "blocked_status": return "Blocked"
        case "behind": return "Branch is behind"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func icon(_ status: String) -> String {
        switch status {
        case "success", "passed", "merged", "ready": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "running": return "circle.dotted.circle"
        case "manual": return "pause.circle"
        case "canceled", "cancelled": return "slash.circle"
        case "skipped": return "minus.circle"
        default: return "clock"
        }
    }
}

final class InboxViewState: ObservableObject {
    @Published var selectedPipeline: Pipeline? = nil
    @Published var selectedGroup: [Pipeline] = []
    @Published var groupJobs: [Int: [Job]] = [:]
    @Published var selectedMR: MergeRequest? = nil
    var resize: (NSSize) -> Void = { _ in }
    @Published var maximumHeight: CGFloat = 700
    @Published var contentHeight: CGFloat = 450
    @Published var chromeHeight: CGFloat = 70
    @Published var logTab = "Logs"
    @Published var confirmingMerge = false
    @Published var confirmingClose = false
    @Published var mrDescription = ""
    @Published var mrAuthor = ""
    @Published var mrLoading = false
    @Published var mrError: String?
    @Published var mrJobs: [Job] = []
    @Published var mrTab: String = "Overview"
    @Published var expandedHistory: String?
    @Published var historyJobs: [String: [Job]] = [:]
    @Published var historyLoading: String?
    @Published var historyError: String?
    @Published var history: Bool = false
    @Published var showOtherCompletions = false
    @Published var notifications = false
    @Published var eventFilter = "All"
    @Published var settings: Bool = false
    @Published var logJob: Job? = nil
    @Published var jobs: [Job] = []
    @Published var loadingJobs: Bool = false
    @Published var logText: String = ""
    @Published var loadingLog: Bool = false
    @Published var search: String = ""
    @Published var loadError: String? = nil
    @Published var requestID: UUID = UUID()
    @Published var logRequestID: UUID = UUID()

    func returnToOverview() {
        requestID = UUID()
        logRequestID = UUID()
        selectedPipeline = nil
        selectedGroup = []
        groupJobs = [:]
        selectedMR = nil
        logJob = nil
        settings = false
        notifications = false
        history = false
        confirmingMerge = false
        confirmingClose = false
        loadError = nil
        jobs = []
        loadingJobs = false
    }
}

private struct InboxContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct InboxChromeHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

/// Stage columns stay as wide as their names. Links between them grow when the
/// row has room, and stay short when the row has to scroll.
private struct StageTrack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = ideals.reduce(0) { $0 + $1.width }
        let height = ideals.map(\.height).max() ?? 0
        return CGSize(width: max(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = ideals.reduce(0) { $0 + $1.width }
        let linkCount = subviews.indices.filter { $0 % 2 == 1 }.count
        let extraEach = linkCount > 0 ? max(0, bounds.width - contentWidth) / CGFloat(linkCount) : 0
        var x = bounds.minX
        for index in subviews.indices {
            let width = ideals[index].width + (index % 2 == 1 ? extraEach : 0)
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: ideals[index].height))
            x += width
        }
    }
}

struct InboxView: View {
    @ObservedObject var model: InboxModel
    @ObservedObject var state: InboxViewState

    /// Pipeline detail is padded 12pt on each side of this panel.
    private static let inboxWidth: CGFloat = 430

    private var fittedSize: NSSize {
        let height = state.selectedMR == nil ? ceil(state.contentHeight + state.chromeHeight + 2) : 540
        return NSSize(width: state.selectedMR == nil ? Self.inboxWidth : 620,
                      height: min(state.maximumHeight, max(160, height)))
    }

    private var screenTitle: String {
        if state.logJob != nil { return "Job logs" }
        if state.selectedGroup.count > 1 { return PipelineModel.groupTitle(state.selectedGroup) }
        if state.selectedMR?.host == .github { return "Pull request" }
        if state.selectedMR != nil { return "Merge request" }
        if state.selectedPipeline != nil { return "Pipeline" }
        if state.settings { return "Preferences" }
        if state.notifications { return "Notifications" }
        if state.history { return "Recent successes" }
        return "Pipeline Tracer"
    }
    private var canGoBack: Bool {
        state.selectedPipeline != nil || state.selectedMR != nil || state.settings || state.notifications || state.history
    }
    private var failures: [Pipeline] { PipelineModel.unresolvedFailures(model.pipelines) }
    private var failureGroups: [PipelineGroup] { PipelineModel.groupSameChange(failures) }
    private var active: [Pipeline] { model.pipelines.filter { $0.isRunning || $0.status == "manual" } }
    private var activeGroups: [PipelineGroup] { PipelineModel.groupSameChange(active) }
    private var finished: [Pipeline] { model.pipelines.filter { $0.status == "success" || $0.status == "passed" } }
    private var otherCompletions: [Pipeline] { model.pipelines.filter { ["canceled", "cancelled", "skipped"].contains($0.status) } }
    private var mergedEvents: [ActivityEvent] { model.events.filter { $0.status == "merged" } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if canGoBack {
                    Button(action: resetDetail) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text(screenTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .buttonStyle(BackButtonStyle())
                    .help("Back")
                } else {
                    Text(screenTitle).font(.headline)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh")
                Button { resetDetail(); state.notifications = true } label: { Image(systemName: "bell") }.buttonStyle(.plain).help("Notifications")
                Button { resetDetail(); state.settings = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Preferences")
            }.padding(.horizontal, 14).padding(.vertical, 8)
                .background(GeometryReader { geometry in Color.clear.preference(key: InboxChromeHeight.self, value: geometry.size.height) })
            Divider().overlay(Color.white.opacity(0.08))
            if let mr = state.selectedMR { mrWorkspace(mr) } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if state.settings { preferences }
                    else if state.notifications { notificationsView }
                    else if state.selectedGroup.count > 1 {
                        groupedPipelineDetail(state.selectedGroup)
                    } else if let p = state.selectedPipeline {
                        pipelineDetail(p)
                    } else if state.history { successView }
                    else { overview }
                }.padding(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in Color.clear.preference(key: InboxContentHeight.self, value: geometry.size.height) })
            }.id(state.settings ? "preferences" : state.notifications ? "notifications" : state.logJob.map { "log-\($0.id)" } ?? state.selectedPipeline.map { "pipeline-\($0.key)" } ?? (state.history ? "history" : "overview"))
            }
            Divider()
            HStack {
                Text(model.updated.map { (model.preview ? "Preview · " : "Updated ") + "" + $0.formatted(date: .omitted, time: .shortened) } ?? "Connecting…")
                Spacer()
                Text("\(model.mrs.count) MRs · \(activeGroups.count) active")
            }.font(.system(size: 10)).foregroundColor(.secondary).padding(8)
                .background(GeometryReader { geometry in Color.clear.preference(key: InboxChromeHeight.self, value: geometry.size.height) })
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .onPreferenceChange(InboxContentHeight.self) { if $0 > 0 { state.contentHeight = $0 } }
        .onPreferenceChange(InboxChromeHeight.self) { if $0 > 0 { state.chromeHeight = $0 } }
        .onChange(of: fittedSize) { state.resize($0) }
        .onAppear { state.resize(fittedSize) }
        .onReceive(model.$mrs) { list in
            guard let current = state.selectedMR, !state.mrLoading, !state.confirmingMerge, !state.confirmingClose else { return }
            guard var fresh = list.first(where: { $0.key == current.key }) else { state.mrError = "This \(current.host == .github ? "pull request" : "merge request") is no longer in the open list. Refresh or open \(current.host == .github ? "GitHub" : "GitLab")."; return }
            if fresh.pipelineStatus == nil { fresh.pipelineStatus = current.pipelineStatus }
            state.selectedMR = fresh
        }
        .background(Deck.background)
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .tint(Deck.cyan)
        .allowsHitTesting(!state.confirmingMerge && !state.confirmingClose)
        .overlay {
            if state.confirmingMerge, let mr = state.selectedMR {
                ZStack { Color.black.opacity(0.45); mergeConfirmation(mr).frame(width: 290).shadow(color: .black.opacity(0.4), radius: 20) }
            } else if state.confirmingClose, let mr = state.selectedMR {
                ZStack { Color.black.opacity(0.45); closeConfirmation(mr).frame(width: 290).shadow(color: .black.opacity(0.4), radius: 20) }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let error = model.error {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundColor(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Deck.card).cornerRadius(8)
            }
            if let result = model.result, !model.preview {
                Text(result).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if !failureGroups.isEmpty {
                heading("Attention needed", count: failureGroups.count, color: .red)
                panel {
                    ForEach(Array(failureGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { rowDivider }
                        pipelineGroupRow(group)
                    }
                }
            }
            heading("In progress", count: activeGroups.count, color: Deck.cyan)
            panel {
                if activeGroups.isEmpty { compactEmpty(model.refreshing && model.updated == nil ? "Loading pipelines…" : "No active pipelines") }
                ForEach(Array(activeGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { rowDivider }
                    pipelineGroupRow(group)
                }
            }
            heading("Requests", count: model.mrs.count, color: Deck.cyan)
            panel {
                if model.mrs.isEmpty { compactEmpty(model.refreshing && model.updated == nil ? "Loading requests…" : "No open requests") }
                ForEach(Array(model.mrs.enumerated()), id: \.element.key) { index, mr in
                    if index > 0 { rowDivider }
                    mrRow(mr)
                }
            }
            panel {
                Button { state.history = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Recent successes").font(.system(size: 12, weight: .semibold))
                        countLabel(finished.count + mergedEvents.count, .green)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(InboxRowStyle())
            }
            if !otherCompletions.isEmpty {
                panel {
                    Button { state.showOtherCompletions.toggle() } label: {
                        HStack(spacing: 8) {
                            Text("Canceled & skipped").font(.system(size: 12, weight: .semibold))
                            countLabel(otherCompletions.count, .secondary)
                            Spacer()
                            Image(systemName: state.showOtherCompletions ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(InboxRowStyle())
                    if state.showOtherCompletions {
                        ForEach(Array(otherCompletions.enumerated()), id: \.element.id) { index, p in
                            rowDivider
                            pipelineRow(p)
                        }
                    }
                }
            }
        }
    }

    private var successView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { state.history = false } label: {
                HStack(spacing: 8) {
                    Label("Recent successes", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                    countLabel(finished.count + mergedEvents.count, .green)
                    Spacer()
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(InboxRowStyle())
            Text("\(PipelineTracerPrefs.pipelineHours)-hour pipeline window · merge events from this session").font(.system(size: 9)).foregroundColor(.secondary)
            panel {
                    if finished.isEmpty && mergedEvents.isEmpty { compactEmpty("No recent completions") }
                    ForEach(Array(finished.prefix(30).enumerated()), id: \.element.id) { _, p in
                        rowDivider
                        pipelineRow(p, expandHistory: true)
                        if state.expandedHistory == p.key {
                            if state.historyLoading != nil { ProgressView().controlSize(.small).padding(8) }
                            if let error = state.historyError { Text(error).font(.caption2).foregroundColor(.orange).padding(8) }
                            ForEach(state.historyJobs[p.key] ?? p.jobs, id: \.id) { job in
                                HStack(spacing: 8) {
                                    Image(systemName: Deck.icon(job.status)).foregroundColor(Deck.color(job.status))
                                    Text(job.name).lineLimit(1)
                                    Spacer()
                                    Text(job.duration.map { duration($0) } ?? "—").foregroundColor(.secondary)
                                    Button("View logs") { select(p); loadLog(job, pipeline: p) }.buttonStyle(DeckInlineStyle())
                                }.font(.system(size: 10)).padding(.leading, 34).padding(.trailing, 10).padding(.vertical, 6)
                            }
                        }
                    }
                    ForEach(mergedEvents) { event in
                        rowDivider
                        Button { open(event.url) } label: {
                            HStack { Image(systemName: "arrow.triangle.merge").foregroundColor(.green); VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.system(size: 11, weight: .medium)); Text(event.detail).font(.system(size: 10)).foregroundColor(.secondary) }; Spacer(); Text(relative(event.date)).font(.system(size: 9)).foregroundColor(.secondary) }.padding(10)
                        }.buttonStyle(InboxRowStyle())
                    }

            }
        }
    }

    private var rowDivider: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 10) }
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content).frame(maxWidth: .infinity)
            .background(Deck.card.opacity(0.7)).cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    private func compactEmpty(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func countLabel(_ count: Int, _ color: Color) -> some View {
        Text("\(count)").font(.system(size: 10, weight: .semibold)).foregroundColor(color).padding(.horizontal, 5).padding(.vertical, 2).background(color.opacity(0.10)).clipShape(Capsule())
    }
    private func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes == 0 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 1440 { return "\(minutes / 60)h ago" }
        return "\(minutes / 1440)d ago"
    }
    /// Green ready, orange waiting (approval/CI), red blocked, gray draft/other.
    private func mrTone(_ mr: MergeRequest) -> String {
        if mr.isReady { return "ready" }
        if mr.draft { return "pending" }
        switch mr.mergeStatus {
        case "conflict", "broken_status", "blocked_status", "policies_denied":
            return "failed"
        case "ci_still_running", "ci_must_pass", "not_approved", "approvals_syncing",
             "discussions_not_resolved", "requested_changes", "checking", "unchecked",
             "external_status_checks", "preparing", "prepared", "behind":
            return "running"
        default:
            break
        }
        if mr.pipelineStatus == "failed" { return "failed" }
        if mr.pipelineStatus == "running" { return "running" }
        return "pending"
    }
    private func mrState(_ mr: MergeRequest) -> String {
        mr.draft ? "Draft" : mr.isReady ? "Ready to merge" : Deck.title(mr.mergeStatus)
    }
    private func mrRow(_ mr: MergeRequest) -> some View {
        let tone = mrTone(mr)
        let color = Deck.color(tone)
        return Button { showMR(mr) } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 19, weight: .medium)).foregroundColor(color).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(mr.numberLabel)  \(mr.title)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(mr.project).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(mrState(mr)).font(.system(size: 10)).foregroundColor(color).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(InboxRowStyle()).help("\(mr.numberLabel) \(mr.title) — \(mrState(mr))")
    }

    private func pipelineGroupRow(_ group: PipelineGroup) -> some View {
        if group.pipelines.count == 1 { return AnyView(pipelineRow(group.pipelines[0])) }
        let branch = group.pipelines.first { $0.mergeRequestIID == nil }
        let mr = group.pipelines.first { $0.mergeRequestIID != nil }
        let title = PipelineModel.groupTitle(group.pipelines)
        let when = group.pipelines.compactMap(\.updated).max()
        return AnyView(Button { selectGroup(group.pipelines) } label: {
            HStack(spacing: 10) {
                progressRing(group.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text("\(group.primary.project) · MR !\(mr?.mergeRequestIID ?? 0)").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    HStack(spacing: 8) {
                        if let mr { Text("MR !\(mr.mergeRequestIID ?? 0) · \(Deck.title(mr.status))") }
                        if let branch { Text("branch · \(Deck.title(branch.status))") }
                    }.font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(relative(when)).font(.system(size: 10)).foregroundColor(.secondary).fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(InboxRowStyle()))
    }

    private func groupedPipelineDetail(_ pipelines: [Pipeline]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PipelineModel.groupTitle(pipelines)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text("\(pipelines[0].project) · one change, two GitLab pipelines").font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let error = state.loadError { Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.system(size: 10)) }
            ForEach(pipelines, id: \.id) { pipeline in
                let jobs = state.groupJobs[pipeline.id] ?? pipeline.jobs
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(pipeline.mergeRequestIID == nil ? "Branch" : "MR !\(pipeline.mergeRequestIID ?? 0)")
                            .font(.system(size: 11, weight: .semibold))
                        Text("#\(pipeline.id)").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        Spacer()
                        badge(pipeline.status, pipeline.status)
                        Button { open(pipeline.url) } label: { Image(systemName: "arrow.up.right.square").foregroundColor(Deck.cyan) }.buttonStyle(.plain)
                    }
                    Text(pipeline.mergeRequestIID == nil ? pipeline.ref : "refs/merge-requests/\(pipeline.mergeRequestIID ?? 0)/head")
                        .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    if state.loadingJobs && jobs.isEmpty { ProgressView("Loading jobs…").controlSize(.small) }
                    if !jobs.isEmpty {
                        panel {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                if index > 0 { rowDivider }
                                HStack(spacing: 8) {
                                    Image(systemName: Deck.icon(job.status)).foregroundColor(Deck.color(job.status)).frame(width: 15)
                                    Text(job.name).font(.system(size: 11)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(job.duration.map { duration($0) } ?? Deck.title(job.status)).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                    Button("View logs") { loadLog(job, pipeline: pipeline) }.buttonStyle(DeckInlineStyle())
                                }.padding(.horizontal, 10).padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    private func pipelineRow(_ p: Pipeline, expandHistory: Bool = false) -> some View {
        Button { if expandHistory { toggleHistory(p) } else { select(p) } } label: {
            HStack(spacing: 10) {
                if p.isFailed { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 23)).foregroundColor(.red).frame(width: 30) }
                else { progressRing(p) }
                if p.isRunning {
                    Text(p.jobs.isEmpty ? "—" : "\(completed(p.jobs))/\(p.jobs.count)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).frame(width: 29)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 25)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.isFailed ? "Pipeline failed" : (p.workflow.isEmpty ? "Pipeline #\(String(p.id))" : p.workflow)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text("\(p.project) · \(p.refLabel)").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    if p.isFailed, let failed = p.jobs.first(where: { $0.status == "failed" }) { Text("\(failed.name) failed").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(relative(p.updated)).font(.system(size: 10)).foregroundColor(.secondary).fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(InboxRowStyle()).help("\(p.project) #\(String(p.id)) · \(p.refLabel) · \(Deck.title(p.status))")
    }

    private func toggleHistory(_ p: Pipeline) {
        let key = p.key
        if state.expandedHistory == key { state.expandedHistory = nil; return }
        state.expandedHistory = key; state.historyError = nil
        if model.preview { state.historyJobs[key] = p.jobs; return }
        state.historyLoading = key
        DispatchQueue.global(qos: .utility).async {
            let result = PipelineModel.jobsForPipeline(p)
            DispatchQueue.main.async {
                guard state.expandedHistory == key else { return }
                state.historyLoading = nil
                switch result {
                case .success(let jobs): state.historyJobs[key] = jobs
                case .failure: state.historyError = "Couldn’t load completed jobs. Open the pipeline in \(p.serviceName)."
                }
            }
        }
    }

    private var notificationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabBar([("All", "All"), ("Pipelines", "Pipelines"), ("Merges", "Merges")], selection: $state.eventFilter)
            let events = model.events.filter { state.eventFilter == "All" || (state.eventFilter == "Merges" ? $0.url.contains("/merge_requests/") || $0.url.contains("/pull/") || $0.title.hasPrefix("Merge") : !$0.url.contains("/merge_requests/") && !$0.url.contains("/pull/") && !$0.title.hasPrefix("Merge")) }
            if events.isEmpty { compactEmpty("No notifications this session") }
            ForEach(eventGroups(events), id: \.self) { project in
                Text(project).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                panel {
                    ForEach(Array(events.filter { eventProject($0) == project }.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { rowDivider }
                        HStack(alignment: .center, spacing: 9) {
                            Image(systemName: Deck.icon(event.status)).foregroundColor(Deck.color(event.status)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.system(size: 11, weight: .semibold))
                                Text(event.detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(relative(event.date)).font(.system(size: 9)).foregroundColor(.secondary)
                                Button(event.title.localizedCaseInsensitiveContains("connection") ? "Retry" : event.url.contains("/merge_requests/") ? "View MR" : event.url.contains("/pull/") ? "View PR" : event.url.contains("/jobs/") ? "View logs" : "View pipeline") { if event.title.localizedCaseInsensitiveContains("connection") { model.refresh() } else { activateEvent(event) } }.buttonStyle(DeckInlineStyle())
                            }
                        }.padding(10).background(event.status == "failed" ? Color.red.opacity(0.06) : Color.clear)
                    }
                }
            }
            Text("This session · failures alert with sound; routine successes stay quiet").font(.system(size: 9)).foregroundColor(.secondary)
        }
    }
    private func eventProject(_ event: ActivityEvent) -> String { event.detail.components(separatedBy: " ").first ?? "Pipeline Tracer" }
    private func eventGroups(_ events: [ActivityEvent]) -> [String] { var seen = Set<String>(); return events.map(eventProject).filter { seen.insert($0).inserted } }
    private func activateEvent(_ event: ActivityEvent) {
        if let pipeline = model.pipelines.first(where: { $0.url == event.url || $0.jobs.contains(where: { $0.url == event.url }) }) {
            state.notifications = false
            select(pipeline)
            if event.status == "failed", let job = pipeline.jobs.first(where: { $0.status == "failed" }) { loadLog(job, pipeline: pipeline) }
        } else { open(event.url) }
    }

    private func progressRing(_ p: Pipeline) -> some View {
        let progress = p.jobs.isEmpty ? ((p.status == "success" || p.status == "passed") ? 1.0 : 0) : Double(completed(p.jobs)) / Double(p.jobs.count)
        return ZStack {
            Circle().stroke(Deck.color(p.status).opacity(0.22), lineWidth: 3)
            Circle().trim(from: 0, to: progress).stroke(Deck.color(p.status), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            if !p.jobs.isEmpty {
                Text("\(completed(p.jobs))/\(p.jobs.count)").font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundColor(Deck.color(p.status))
            } else { Image(systemName: Deck.icon(p.status)).font(.system(size: 10)).foregroundColor(Deck.color(p.status)) }
        }.frame(width: 26, height: 26).accessibilityLabel(p.jobs.isEmpty ? "\(p.status), job details not loaded" : "\(p.status), \(completed(p.jobs)) of \(p.jobs.count) jobs finished")
    }

    private func pipelineDetail(_ p: Pipeline) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(String(p.id))  \(p.project)").font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Text("\(p.refLabel) · \(relative(p.updated))").font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer(minLength: 5)
                badge(p.status, p.status)
                Button { open(p.url) } label: { Image(systemName: "arrow.up.right.square").foregroundColor(Deck.cyan) }.buttonStyle(.plain).help("Open pipeline on \(p.serviceName)")
            }
            if let error = state.loadError { Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.system(size: 10)) }
            if state.loadingJobs && state.logJob == nil { ProgressView("Loading jobs…").controlSize(.small) }
            if let job = state.logJob {
                panel {
                    HStack(spacing: 8) {
                        Image(systemName: Deck.icon(job.status)).foregroundColor(Deck.color(job.status))
                        Text(job.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(job.duration.map { duration($0) } ?? "").font(.system(size: 10)).foregroundColor(.secondary)
                        Button("All jobs") { state.logRequestID = UUID(); state.logJob = nil; state.loadError = nil; state.loadingLog = false }.buttonStyle(.borderless).font(.system(size: 10))
                    }.padding(10)
                }
                tabBar([( "Logs", "Logs"), ("Summary", "Job summary")], selection: $state.logTab)
                if state.logTab == "Logs" {
                    HStack(spacing: 6) {
                        TextField("Search logs…", text: $state.search).textFieldStyle(.roundedBorder).font(.system(size: 10))
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.logText, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(DeckInlineStyle()).disabled(state.loadingLog || state.logText.isEmpty)
                        Button { open(job.url) } label: { Label(p.serviceName, systemImage: "arrow.up.right.square") }.buttonStyle(DeckInlineStyle())
                    }
                    if state.loadingLog { ProgressView("Loading log…").controlSize(.small) }
                    ScrollView(.horizontal) {
                        Text(formattedLog).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false).frame(minWidth: 360, minHeight: 250, alignment: .topLeading).padding(10)
                    }.background(Color.black.opacity(0.28)).cornerRadius(7)
                    Text("Log snapshot · latest 250,000 characters · \(visibleLog.components(separatedBy: "\n").count) visible lines").font(.system(size: 9)).foregroundColor(.secondary)
                } else {
                    panel {
                        VStack(spacing: 12) {
                            metadata("Job", job.name)
                            metadata("Stage", job.stage)
                            metadata("Status", Deck.title(job.status))
                            metadata("Duration", job.duration.map { duration($0) } ?? "Not reported")
                        }.padding(12)
                    }
                    Button("Open job on \(p.serviceName)") { open(job.url) }.buttonStyle(DeckActionStyle())
                }
            } else {
                if !state.jobs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: true) {
                        StageTrack {
                            ForEach(stagePieces, id: \.self) { piece in
                                switch piece {
                                case .link:
                                    Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1).frame(minWidth: 12, idealWidth: 12, maxWidth: .infinity).padding(.top, 12)
                                case .stage(let stage):
                                    stageColumn(stage)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        .frame(minWidth: Self.inboxWidth - 24, alignment: .leading)
                    }
                    HStack { Text("Jobs (\(state.jobs.count))").font(.system(size: 11, weight: .semibold)); Spacer(); Text("\(completed(state.jobs)) finished").font(.system(size: 10)).foregroundColor(.secondary) }
                    panel {
                        ForEach(Array(state.jobs.enumerated()), id: \.element.id) { index, job in
                            if index > 0 { rowDivider }
                            HStack(spacing: 8) {
                                Image(systemName: Deck.icon(job.status)).foregroundColor(Deck.color(job.status)).frame(width: 15)
                                Text(job.name).font(.system(size: 11)).lineLimit(1).help(job.name)
                                Spacer(minLength: 4)
                                Text(job.duration.map { duration($0) } ?? Deck.title(job.status)).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                Button("View logs") { loadLog(job, pipeline: p) }.buttonStyle(DeckInlineStyle())
                            }.padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                } else if !state.loadingJobs && state.loadError == nil { compactEmpty("No jobs available · Open \(p.serviceName) for details") }
            }
        }
    }
    private var visibleLog: String {
        state.search.isEmpty ? state.logText : state.logText.components(separatedBy: "\n").filter { $0.localizedCaseInsensitiveContains(state.search) }.joined(separator: "\n")
    }
    private var formattedLog: AttributedString {
        var value = AttributedString()
        for line in visibleLog.components(separatedBy: "\n") {
            var segment = AttributedString(line + "\n")
            segment.foregroundColor = line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("fail") ? .red : .white.opacity(0.85)
            value.append(segment)
        }
        return value
    }

    private func mrWorkspace(_ mr: MergeRequest) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Requests").font(.system(size: 12, weight: .semibold)); countLabel(model.mrs.count, Deck.cyan) }.padding(.bottom, 8)
                    ForEach(model.mrs, id: \.key) { item in
                        let color = Deck.color(mrTone(item))
                        Button { showMR(item) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.triangle.branch").foregroundColor(color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(item.numberLabel)  \(item.title)").font(.system(size: 11, weight: .medium)).lineLimit(2)
                                    Text(item.project).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                                    Text(mrState(item)).font(.system(size: 9)).foregroundColor(color)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(9).background(item.key == mr.key ? Deck.cyan.opacity(0.12) : Color.clear).cornerRadius(7)
                        }.buttonStyle(.plain)
                    }
                }.padding(12)
            }.frame(width: 275)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.triangle.branch").foregroundColor(Deck.cyan)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(mr.numberLabel)  \(mr.title)").font(.system(size: 13, weight: .semibold))
                            Text(mr.project).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { open(mr.url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help(mr.host == .github ? "Open pull request on GitHub" : "Open merge request in GitLab")
                    }
                    badge(mrState(mr), mrTone(mr))
                    if state.mrLoading { ProgressView("Loading merge request…").controlSize(.small) }
                    if let error = state.mrError { Text(error).font(.caption).foregroundColor(.orange) }
                    if !state.mrDescription.isEmpty {
                        Text((try? AttributedString(markdown: descriptionSummary(state.mrDescription), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(descriptionSummary(state.mrDescription))).font(.system(size: 11)).lineLimit(6).textSelection(.enabled)
                    }
                    VStack(spacing: 10) {
                        metadata("Source", mr.sourceBranch.isEmpty ? "Not reported" : mr.sourceBranch)
                        metadata("Target", mr.targetBranch.isEmpty ? "Not reported" : mr.targetBranch)
                        if !state.mrAuthor.isEmpty { metadata("Author", state.mrAuthor) }
                    }
                    panel {
                        HStack(spacing: 8) {
                            Image(systemName: Deck.icon(mr.pipelineStatus ?? "pending")).foregroundColor(Deck.color(mr.pipelineStatus ?? "pending"))
                            Text("\(mr.host == .github ? "Checks" : "Pipeline"): \(Deck.title(mr.pipelineStatus ?? "not reported"))").font(.system(size: 11, weight: .medium))
                            Spacer()
                        }.padding(10)
                        ForEach(state.mrJobs, id: \.id) { job in
                            rowDivider
                            HStack { Image(systemName: Deck.icon(job.status)).foregroundColor(Deck.color(job.status)); Text(job.name).lineLimit(1); Spacer(); Text(job.duration.map { duration($0) } ?? "—").foregroundColor(.secondary) }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 7)
                        }
                    }
                    HStack(spacing: 8) {
                        if PipelineTracerPrefs.mergeButton && mr.canMerge {
                            Button {
                                state.confirmingMerge = true
                            } label: {
                                HStack(spacing: 6) {
                                    if !mr.isReady {
                                        Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                                    }
                                    Text(model.merging == mr.key ? "Merging…" : "Merge")
                                }
                            }
                            .buttonStyle(DeckActionStyle(primary: true))
                            .disabled(!mr.isReady || model.merging != nil || model.closing != nil || state.mrLoading || state.mrError != nil)
                            .frame(maxWidth: .infinity)
                        }
                        Button {
                            state.confirmingClose = true
                        } label: {
                            Text(model.closing == mr.key ? "Closing…" : (mr.host == .github ? "Close PR" : "Close MR"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .buttonStyle(DeckActionStyle())
                        .disabled(model.merging != nil || model.closing != nil || state.mrLoading)
                        .fixedSize(horizontal: PipelineTracerPrefs.mergeButton && mr.canMerge, vertical: false)
                    }
                    if PipelineTracerPrefs.mergeButton && mr.canMerge {
                        Text(mr.isReady ? "Ready to merge." : "Merge unavailable: \(mrState(mr)).")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(mr.isReady ? .green : .red)
                    }
                }.padding(14)
            }.frame(maxWidth: .infinity)
        }
    }
    private func descriptionSummary(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        var lines: [String] = []
        for line in clean.components(separatedBy: "\n") {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("|") {
                let cells = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.allSatisfy({ "-: ".contains($0) }) }) || cells.first == "Package" { continue }
                lines.append(cells.joined(separator: " · "))
            } else if !value.isEmpty && value != "---" { lines.append(value) }
            if lines.joined(separator: "\n").count > 350 || lines.count >= 4 { break }
        }
        return String(lines.joined(separator: "\n\n").prefix(500))
    }
    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundColor(.secondary).frame(width: 48, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 10))
    }
    private func mergeConfirmation(_ mr: MergeRequest) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 25)).foregroundColor(Deck.cyan)
            Text(mr.host == .github ? "Merge pull request?" : "Merge request?").font(.system(size: 13, weight: .semibold))
            Text("Merge \(mr.numberLabel) in \(mr.project)").font(.system(size: 11)).multilineTextAlignment(.center)
            Text("\(mr.sourceBranch) → \(mr.targetBranch)").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            HStack {
                Button("Cancel") { state.confirmingMerge = false }.buttonStyle(DeckActionStyle()).keyboardShortcut(.cancelAction)
                Button("Merge") { state.confirmingMerge = false; model.merge(mr) }.buttonStyle(DeckActionStyle(primary: true))
            }
        }.padding(16).frame(maxWidth: .infinity).background(Deck.card).cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(Deck.cyan.opacity(0.3)))
    }
    private func closeConfirmation(_ mr: MergeRequest) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle").font(.system(size: 25)).foregroundColor(.orange)
            Text(mr.host == .github ? "Close pull request?" : "Close merge request?").font(.system(size: 13, weight: .semibold))
            Text("Close \(mr.numberLabel) in \(mr.project)").font(.system(size: 11)).multilineTextAlignment(.center)
            Text("Leaves the source branch as-is. This does not delete anything.").font(.system(size: 10)).foregroundColor(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel") { state.confirmingClose = false }.buttonStyle(DeckActionStyle()).keyboardShortcut(.cancelAction)
                Button(mr.host == .github ? "Close PR" : "Close MR") { state.confirmingClose = false; model.close(mr) }.buttonStyle(DeckActionStyle(primary: true))
            }
        }.padding(16).frame(maxWidth: .infinity).background(Deck.card).cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35)))
    }
    private func mrDetail(_ mr: MergeRequest) -> some View { mrWorkspace(mr) }
    private func showMR(_ mr: MergeRequest) {
        state.selectedMR = mr; state.confirmingMerge = false; state.confirmingClose = false; state.mrError = nil; state.mrJobs = []
        state.mrDescription = ""; state.mrAuthor = ""; state.mrLoading = false
        let token = UUID(); state.requestID = token
        if model.preview {
            state.mrDescription = "Redesign the portfolio with a responsive layout and clearer navigation."
            state.mrAuthor = "example"
            state.mrJobs = model.pipelines.first(where: { $0.projectID == mr.projectID && $0.status == "success" })?.jobs ?? []
            return
        }
        state.mrLoading = true
        if mr.host == .github {
            DispatchQueue.global(qos: .utility).async {
                let detail = PipelineModel.githubPullDetail(mr)
                DispatchQueue.main.async {
                    guard state.requestID == token else { return }
                    state.mrLoading = false
                    if let detail {
                        state.selectedMR = detail.request
                        state.mrDescription = detail.body
                        state.mrAuthor = detail.author
                        state.mrJobs = detail.jobs
                    } else { state.mrError = "Couldn’t refresh pull request details. Open GitHub or try again." }
                }
            }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let detail = Shell.glabJSON("projects/\(mr.projectID)/merge_requests/\(String(mr.iid))") as? [String: Any]
            let fresh = detail.flatMap { PipelineModel.parse($0) }
            var checks: [Job] = []
            if let pipeline = detail?["head_pipeline"] as? [String: Any], let id = pipeline["id"] as? Int { checks = PipelineModel.fetchJobs(projectID: mr.projectID, pipelineID: id) }
            DispatchQueue.main.async {
                guard state.requestID == token else { return }
                state.mrLoading = false
                if let fresh {
                    state.selectedMR = fresh
                    state.mrDescription = detail?["description"] as? String ?? ""
                    state.mrAuthor = (detail?["author"] as? [String: Any])?["username"] as? String ?? ""
                    state.mrJobs = checks
                } else { state.mrError = "Couldn’t refresh merge details. Open GitLab or try again." }
            }
        }
    }
    private func tabBar(_ items: [(String, String)], selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { key, title in
                Button { selection.wrappedValue = key } label: {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(selection.wrappedValue == key ? Deck.cyan : .secondary).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selection.wrappedValue == key ? Deck.cyan.opacity(0.08) : Color.clear)
                        .overlay(alignment: .bottom) { if selection.wrappedValue == key { Rectangle().fill(Deck.cyan).frame(height: 2) } }
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
    private func duration(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value < 60 ? "\(value)s" : "\(value / 60)m \(value % 60)s"
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Panel").font(.system(size: 12, weight: .semibold))
            panel {
                preferenceToggle("Reopen where I left off", value: PipelineTracerPrefs.rememberPlace, refresh: false) { PipelineTracerPrefs.rememberPlace = $0 }
            }
            Text("Pipelines").font(.system(size: 12, weight: .semibold))
            panel {
                preferenceChoice("Refresh interval", options: PipelineTracerPrefs.refreshChoices, value: PipelineTracerPrefs.refreshSeconds, suffix: "seconds") { PipelineTracerPrefs.refreshSeconds = $0; model.refresh() }
                rowDivider
                preferenceChoice("Completion history", options: PipelineTracerPrefs.pipelineHourChoices, value: PipelineTracerPrefs.pipelineHours, suffix: "hours") { PipelineTracerPrefs.pipelineHours = $0; model.refresh() }
                rowDivider
                preferenceToggle("Show merge actions", value: PipelineTracerPrefs.mergeButton) { PipelineTracerPrefs.mergeButton = $0 }
            }
            Text("Notifications").font(.system(size: 12, weight: .semibold))
            panel {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Failures alert · successes stay quiet", systemImage: "bell.badge").font(.system(size: 11)).foregroundColor(Deck.cyan)
                    if let enabled = model.notificationsEnabled {
                        Label(enabled ? "Banners enabled in macOS" : "Banners disabled in macOS",
                              systemImage: enabled ? "checkmark.circle" : "bell.slash")
                            .font(.system(size: 10)).foregroundColor(enabled ? .green : .orange)
                    }
                    Text("Failures are titled Pipeline Tracer and play a sound. macOS chooses the banner colors. Expand a notification for View MR, View pipeline, or View logs.").font(.system(size: 10)).foregroundColor(.secondary)
                    HStack {
                        Button("Notification settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                        }.buttonStyle(DeckInlineStyle())
                        Button("Send test") { Notifier.preview() }.buttonStyle(DeckInlineStyle())
                            .disabled(model.preview || model.notificationsEnabled != true)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Quit Pipeline Tracer") { NSApp.terminate(nil) }.buttonStyle(DeckInlineStyle()) }
        }
    }
    private func preferenceChoice(_ title: String, options: [Int], value: Int, suffix: String, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundColor(.white)
            Spacer(minLength: 8)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        set(option)
                        model.objectWillChange.send()
                    } label: {
                        if option == value {
                            Label("\(option) \(suffix)", systemImage: "checkmark")
                        } else {
                            Text("\(option) \(suffix)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text("\(value) \(suffix)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Deck.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func preferenceToggle(_ title: String, value: Bool, refresh: Bool = true, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 11))
            Spacer()
            Toggle(title, isOn: Binding(get: { value }, set: { set($0); model.objectWillChange.send(); if refresh { model.refresh() } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Deck.cyan)
        }.padding(.horizontal, 10).padding(.vertical, 8)
    }
    private enum StagePiece: Hashable {
        case stage(String)
        case link(Int)
    }

    /// Stage columns with a link before every stage after the first.
    private var stagePieces: [StagePiece] {
        var pieces: [StagePiece] = []
        for (index, stage) in stages.enumerated() {
            if index > 0 { pieces.append(.link(index)) }
            pieces.append(.stage(stage))
        }
        return pieces
    }

    private func stageColumn(_ stage: String) -> some View {
        let list = state.jobs.filter { $0.stage == stage }
        let status = stageStatus(stage)
        return VStack(spacing: 5) {
            Image(systemName: Deck.icon(status)).font(.system(size: 24)).foregroundColor(Deck.color(status))
            Text(stage).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Text("\(completed(list))/\(list.count) jobs").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 44)
    }

    private func stageStatus(_ stage: String) -> String {
        let statuses = state.jobs.filter { $0.stage == stage }.map(\.status)
        if statuses.contains("failed") { return "failed" }
        if statuses.contains("running") { return "running" }
        if statuses.contains("manual") { return "manual" }
        if statuses.allSatisfy({ $0 == "success" || $0 == "passed" }) { return "success" }
        if statuses.allSatisfy({ $0 == "skipped" }) { return "skipped" }
        if statuses.allSatisfy({ $0 == "canceled" || $0 == "cancelled" }) { return "canceled" }
        return "pending"
    }
    private var stages: [String] { var seen = Set<String>(); return state.jobs.map(\.stage).filter { seen.insert($0).inserted } }
    private func heading(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: title == "In progress" ? "arrow.triangle.branch" : title == "Requests" || title == "Attention needed" ? "arrow.triangle.pull" : "circle.grid.2x2").font(.system(size: 12)).foregroundColor(color).frame(width: 16)
            Text(title).font(.system(size: 12, weight: .semibold))
            countLabel(count, color)
            Spacer()
        }.padding(.horizontal, 2).padding(.top, 2)
    }
    private func badge(_ title: String, _ status: String) -> some View { Label(Deck.title(title), systemImage: Deck.icon(status)).font(.system(size: 10, weight: .medium)).foregroundColor(Deck.color(status)).padding(.horizontal, 7).padding(.vertical, 4).background(Deck.color(status).opacity(0.12)).cornerRadius(6) }
    private func empty(_ title: String, _ subtitle: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline); Text(subtitle).font(.caption).foregroundColor(.secondary) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Deck.card).cornerRadius(10) }
    private func completed(_ list: [Job]) -> Int { list.filter { Notifier.isDone($0.status) }.count }
    private func open(_ url: String) { if let u = Shell.browserURL(url) { NSWorkspace.shared.open(u) } }
    private func resetDetail() { state.returnToOverview() }
    private func selectGroup(_ pipelines: [Pipeline]) {
        resetDetail()
        state.selectedGroup = pipelines
        state.selectedPipeline = pipelines[0]
        for pipeline in pipelines { state.groupJobs[pipeline.id] = pipeline.jobs }
        if model.preview { return }
        state.loadingJobs = true
        let token = UUID(); state.requestID = token
        DispatchQueue.global(qos: .utility).async {
            var loaded: [Int: [Job]] = [:]
            for pipeline in pipelines {
                if case .success(let jobs) = PipelineModel.jobsForPipeline(pipeline) {
                    loaded[pipeline.id] = jobs
                }
            }
            DispatchQueue.main.async {
                guard state.requestID == token else { return }
                state.loadingJobs = false
                for (id, jobs) in loaded { state.groupJobs[id] = jobs }
                if loaded.count != pipelines.count {
                    state.loadError = "Couldn’t load every pipeline. Open the missing one in the browser."
                }
            }
        }
    }
    private func select(_ p: Pipeline) {
        resetDetail(); state.selectedPipeline = p; state.jobs = p.jobs; if model.preview { return }; state.loadingJobs = true
        let token = UUID(); state.requestID = token
        DispatchQueue.global(qos: .utility).async {
            let result = PipelineModel.jobsForPipeline(p)
            DispatchQueue.main.async {
                guard state.requestID == token else { return }
                state.loadingJobs = false
                switch result {
                case .success(let fetched): state.jobs = fetched
                case .failure: state.loadError = "Couldn’t load jobs. Check \(p.serviceName) access or open in browser."
                }
            }
        }
    }
    private func cleanLog(_ text: String) -> String {
        String(text.suffix(250_000))
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "section_(?:start|end):[0-9]+:[^\r\n]*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }
    private func loadLog(_ job: Job, pipeline: Pipeline) {
        state.logJob = job; state.logTab = "Logs"; state.search = ""; state.logText = ""; state.loadingLog = true; state.loadError = nil
        if model.preview {
            state.loadingLog = false
            state.logText = "112  Running integration tests…\n113  Connecting to test database\n114  FAIL test:integration > session timeout\n115  Error: expected 200, received 500\n116  Tests: 1 failed, 12 passed\n117  Process exited with code 1"
            return
        }
        let token = UUID(); state.logRequestID = token
        DispatchQueue.global(qos: .utility).async {
            let result = PipelineModel.jobTrace(job: job, pipeline: pipeline)
            DispatchQueue.main.async {
                guard state.logRequestID == token else { return }
                state.loadingLog = false
                switch result {
                case .text(let text):
                    state.logText = cleanLog(text)
                    if state.logText.isEmpty { state.logText = "No log output yet." }
                case .unavailable:
                    state.loadError = "Couldn’t load log. Open this job on \(pipeline.serviceName)."
                }
            }
        }
    }
}

private struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Rectangle())
    }
}

private struct InboxRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Deck.cyan.opacity(0.12) : Color.clear)
    }
}

private struct DeckActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label.font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                primary
                    ? (enabled ? Deck.cyan.opacity(pressed ? 0.55 : 0.9) : Color.white.opacity(0.08))
                    : Color.white.opacity(enabled ? (pressed ? 0.14 : 0.07) : 0.04)
            )
            .foregroundColor(primary ? (enabled ? Deck.background : Color.white.opacity(0.35)) : Color.white.opacity(enabled ? 1 : 0.55))
            .cornerRadius(6)
    }
}

private struct DeckInlineStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 10, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundColor(enabled ? Color.white.opacity(0.88) : Color.gray)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.04))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.13), lineWidth: 0.5))
    }
}
