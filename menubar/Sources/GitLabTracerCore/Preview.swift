import AppKit
import SwiftUI

/// Local, non-mutating UI review. Fixtures are never mixed into live GitLab state.
public enum Preview {
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let model = InboxModel()
        model.preview = true
        let state = InboxViewState()
        let jobs = [Job(id: 1, name: "build:application", stage: "Build", status: "success", url: "https://gitlab.com", duration: 42), Job(id: 2, name: "test:unit", stage: "Test", status: "success", url: "https://gitlab.com", duration: 18), Job(id: 3, name: "test:integration", stage: "Test", status: "running", url: "https://gitlab.com", duration: 64), Job(id: 4, name: "deploy:production", stage: "Deploy", status: "manual", url: "https://gitlab.com", duration: nil)]
        model.pipelines = [
            Pipeline(projectID: 1, id: 220, project: "example/web", ref: "main", status: "running", url: "https://gitlab.com", updated: Date(), jobs: jobs),
            Pipeline(projectID: 2, id: 418, project: "example/api", ref: "feature/auth", status: "running", url: "https://gitlab.com", updated: Date(), jobs: jobs),
            Pipeline(projectID: 3, id: 36, project: "example/app", ref: "main", status: "waiting_for_resource", url: "https://gitlab.com", updated: Date(), jobs: []),
            Pipeline(projectID: 2, id: 417, project: "example/api", ref: "fix/session", status: "failed", url: "https://gitlab.com", updated: Date(), jobs: jobs.map { Job(id: $0.id, name: $0.name, stage: $0.stage, status: $0.id == 3 ? "failed" : "success", url: $0.url, duration: $0.duration) }),
            Pipeline(projectID: 1, id: 219, project: "example/web", ref: "main", status: "success", url: "https://gitlab.com", updated: Date(), jobs: jobs.map { Job(id: $0.id, name: $0.name, stage: $0.stage, status: "success", url: $0.url, duration: $0.duration) })
        ]
        model.mrs = [MergeRequest(projectID: 1, iid: 5, title: "Portfolio redesign", project: "example/web", url: "https://gitlab.com", draft: false, mergeStatus: "mergeable", pipelineStatus: "success", updated: Date(), sourceBranch: "feature/portfolio", targetBranch: "main"), MergeRequest(projectID: 2, iid: 42, title: "Fix authentication edge case", project: "example/api", url: "https://gitlab.com", draft: false, mergeStatus: "ci_still_running", pipelineStatus: "running", updated: Date()), MergeRequest(projectID: 3, iid: 12, title: "Improve menu bar UI", project: "example/app", url: "https://gitlab.com", draft: true, mergeStatus: "draft_status", pipelineStatus: nil, updated: Date())]
        model.events = [ActivityEvent(title: "Pipeline running", detail: "example/web #220 · test:integration", status: "running", url: "https://gitlab.com"), ActivityEvent(title: "Pipeline queued", detail: "example/app #36 · waiting for resource", status: "pending", url: "https://gitlab.com"), ActivityEvent(title: "Manual job available", detail: "example/app #36 · deploy:production", status: "manual", url: "https://gitlab.com"), ActivityEvent(title: "Connection error", detail: "GitLab Tracer · couldn’t reach GitLab", status: "failed", url: "https://gitlab.com"), ActivityEvent(title: "Pipeline failed", detail: "example/api #417 · test:integration", status: "failed", url: "https://gitlab.com"), ActivityEvent(title: "Pipeline passed", detail: "example/web #219 · main", status: "success", url: "https://gitlab.com"), ActivityEvent(title: "Merge complete", detail: "example/web !4", status: "merged", url: "https://gitlab.com")]
        model.pipelines = model.pipelines.map { pipeline in
            var p = pipeline
            p = Pipeline(projectID: p.projectID, id: p.id, project: p.project, ref: p.ref, status: p.status, url: "https://gitlab.com/\(p.project)/-/pipelines/\(p.id)", updated: p.updated, jobs: p.jobs.map { job in Job(id: job.id, name: job.name, stage: job.stage, status: job.status, url: "https://gitlab.com/\(p.project)/-/jobs/\(job.id)", duration: job.duration) })
            return p
        }
        model.events = model.events.map { event in
            let pipeline = model.pipelines.first { event.detail.contains("#\($0.id)") && event.detail.contains($0.project) }
            return ActivityEvent(title: event.title, detail: event.detail, status: event.status, url: pipeline?.url ?? event.url)
        }
        model.updated = Date()
        model.result = "Preview · sample data · merge actions do not change GitLab"
        model.merge = { mr in model.result = "Preview: merge confirmation for !\(mr.iid) (no action sent)" }
        if CommandLine.arguments.contains("--preview-pipeline") { state.selectedPipeline = model.pipelines[0]; state.jobs = jobs }
        if CommandLine.arguments.contains("--preview-mr") { state.selectedMR = model.mrs[0] }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        state.maximumHeight = min(700, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
        state.resize = { [weak window] size in window?.setContentSize(size) }
        window.title = "GitLab Tracer — Design Preview"
        window.contentView = NSHostingView(rootView: InboxView(model: model, state: state))
        window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        app.run()
    }
}
