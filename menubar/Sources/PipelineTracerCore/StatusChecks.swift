import Foundation

public final class StatusChecks {
    public static func run() {
        let checks = StatusChecks()
        checks.testFailureCountsAsFinishedButNeverPassing()
        checks.testCanceledAndSkippedDoNotBecomePassedFromFinishedJobs()
        checks.testManualWaitAndRunningClassification()
        checks.testDraftCannotBeReady()
        checks.testLaterPipelineForSameCommitClearsFailure()
        checks.testBranchAndMergeRequestPipelinesGroup()
        precondition(GitLabModel.parseDate("2026-10-31T22:10:12.123Z") != nil)
        precondition(GitLabModel.parseDate("2026-10-31T22:10:12Z") != nil)
        checks.testNotificationContent()
        checks.testPanelReturnsToOverviewByDefault()
        checks.testGraphQLHelpers()
        print("11 status/date/notification checks passed")
    }
    func testGraphQLHelpers() {
        precondition(GitLabModel.projectID(fromGraphQL: "gid://gitlab/Project/81197701") == 81197701)
        precondition(GitLabModel.projectID(fromGraphQL: 42) == 42)
        precondition(GitLabModel.normalizeMergeStatus("DRAFT_STATUS") == "draft_status")
        precondition(GitLabModel.normalizeMergeStatus("NOT_APPROVED") == "not_approved")
        precondition(GitLabModel.normalizePipelineStatus("SUCCESS") == "success")
    }
    func testNotificationContent() {
        let body = "Fix e2e: " + String(repeating: "calendar ", count: 30)
        let content = Notifier.content("Merge complete", subtitle: "example/app · !347", body: body,
                                       thread: "mr-347", important: false, url: "https://gitlab.com/group/repo/-/merge_requests/347", kind: .mergeRequest)
        precondition(content.title == "Pipeline Tracer")
        precondition(content.subtitle == "Merge complete")
        precondition(content.body.hasPrefix("example/app · !347"))
        precondition(content.body.count == 90 && content.body.hasSuffix("…"))
        precondition(content.sound == nil && content.interruptionLevel == .active && content.categoryIdentifier == "mergeRequest")
        precondition(content.threadIdentifier == "mr-347")
        let failed = Notifier.content("Job failed", subtitle: "group/repo · #12", body: "test:integration\n failed",
                                      thread: "1:12", important: true, url: "https://gitlab.com/group/repo/-/jobs/42", kind: .logs)
        precondition(failed.title == "Pipeline Tracer")
        precondition(failed.subtitle == "Job failed")
        precondition(failed.body == "group/repo · #12 · test:integration failed")
        precondition(failed.sound != nil && failed.interruptionLevel == .timeSensitive && failed.categoryIdentifier == "logs")
        precondition(failed.userInfo["url"] as? String == "https://gitlab.com/group/repo/-/jobs/42")
    }
    func testPanelReturnsToOverviewByDefault() {
        let key = "gitlabtracer.rememberPlace"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        precondition(!PipelineTracerPrefs.rememberPlace)
        PipelineTracerPrefs.rememberPlace = true
        precondition(PipelineTracerPrefs.rememberPlace)
        if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        let state = InboxViewState()
        state.settings = true
        state.returnToOverview()
        precondition(!state.settings && state.selectedPipeline == nil && state.selectedMR == nil)
    }
    private func pipeline(_ status: String, jobs: [Job] = []) -> Pipeline {
        Pipeline(projectID: 1, id: 2, project: "group/repo", ref: "main", status: status, url: "https://gitlab.com", updated: nil, jobs: jobs)
    }
    private func job(_ status: String, id: Int) -> Job { Job(id: id, name: "job", stage: "test", status: status, url: "", duration: nil) }
    func testFailureCountsAsFinishedButNeverPassing() {
        let (status, fraction) = PipelineProgressRing.state(for: pipeline("failed", jobs: [job("success", id: 1), job("failed", id: 2), job("pending", id: 3)]))
        precondition(status == .failed)
        precondition(abs(fraction - 2.0 / 3.0) < 0.001)
    }
    func testCanceledAndSkippedDoNotBecomePassedFromFinishedJobs() {
        precondition(PipelineProgressRing.state(for: pipeline("canceled", jobs: [job("canceled", id: 1)])).0 == .canceled)
        precondition(PipelineProgressRing.state(for: pipeline("skipped", jobs: [job("skipped", id: 1)])).0 == .skipped)
    }
    func testManualWaitAndRunningClassification() {
        precondition(PipelineProgressRing.state(for: pipeline("running", jobs: [job("manual", id: 1)])).0 == .pending)
        precondition(pipeline("waiting_for_resource").isRunning)
        precondition(!Notifier.isDone("manual"))
        precondition(Notifier.isDone("failed"))
    }
    func testDraftCannotBeReady() {
        let mr = MergeRequest(projectID: 1, iid: 4, title: "Draft", project: "group/repo", url: "", draft: true, mergeStatus: "mergeable", pipelineStatus: "success", updated: nil)
        precondition(!mr.isReady)
    }
    func testLaterPipelineForSameCommitClearsFailure() {
        let failed = Pipeline(projectID: 1, id: 10, project: "example/app", ref: "fix/header", status: "failed", url: "", updated: Date(timeIntervalSince1970: 10), sha: "aaaaaaaaaa")
        let passed = Pipeline(projectID: 1, id: 11, project: "example/app", ref: "refs/merge-requests/17/head", status: "success", url: "", updated: Date(timeIntervalSince1970: 20), sha: "aaaaaaaaaa")
        let main = Pipeline(projectID: 1, id: 12, project: "example/app", ref: "main", status: "success", url: "", updated: Date(timeIntervalSince1970: 30), sha: "bbbbbbbbbb")
        precondition(GitLabModel.unresolvedFailures([main, passed, failed]).isEmpty)
        precondition(GitLabModel.unresolvedFailures([failed]).count == 1)
        precondition(GitLabModel.unresolvedFailures([failed, main]).count == 1)
        let olderPass = Pipeline(projectID: 1, id: 9, project: "example/app", ref: "refs/merge-requests/17/head", status: "success", url: "", updated: Date(timeIntervalSince1970: 1), sha: "aaaaaaaaaa")
        precondition(GitLabModel.unresolvedFailures([failed, olderPass]).count == 1)
    }
    func testBranchAndMergeRequestPipelinesGroup() {
        var mr = Pipeline(projectID: 1, id: 20, project: "example/app", ref: "refs/merge-requests/15/head", status: "running", url: "", updated: Date(timeIntervalSince1970: 20), sha: "different-sha")
        mr.sourceBranch = "feature/header"
        let branch = Pipeline(projectID: 1, id: 19, project: "example/app", ref: "feature/header", status: "running", url: "", updated: Date(timeIntervalSince1970: 19), sha: "branch-sha")
        let main = Pipeline(projectID: 1, id: 21, project: "example/app", ref: "main", status: "running", url: "", updated: Date(timeIntervalSince1970: 21), sha: "main-sha")
        let groups = GitLabModel.groupSameChange([main, mr, branch])
        precondition(groups.count == 2)
        precondition(groups.contains { $0.pipelines.map(\.id).sorted() == [19, 20] })
        precondition(groups.contains { $0.pipelines.map(\.id) == [21] })
        precondition(GitLabModel.groupTitle([mr, branch]) == "feature/header")
        precondition(Pipeline(projectID: 1, id: 1, project: "example/app", ref: "refs/merge-requests/15/head", status: "running", url: "", updated: nil).mergeRequestIID == 15)
        precondition(main.mergeRequestIID == nil)
        let sameSha = Pipeline(projectID: 1, id: 30, project: "example/app", ref: "refs/merge-requests/8/head", status: "running", url: "", updated: nil, sha: "abc")
        let twin = Pipeline(projectID: 1, id: 31, project: "example/app", ref: "feature/other", status: "running", url: "", updated: nil, sha: "abc")
        precondition(GitLabModel.groupSameChange([sameSha, twin, main]).count == 2)
        precondition(!GitLabModel.sameChange(sameSha, main))
    }
}
