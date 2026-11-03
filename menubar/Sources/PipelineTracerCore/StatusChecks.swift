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
        precondition(PipelineModel.parseDate("2026-10-31T22:10:12.123Z") != nil)
        precondition(PipelineModel.parseDate("2026-10-31T22:10:12Z") != nil)
        checks.testNotificationContent()
        checks.testPanelReturnsToOverviewByDefault()
        checks.testGraphQLHelpers()
        checks.testGitHubRunsStaySeparateFromGitLab()
        checks.testGitHubPullRequestStatus()
        print("13 status/date/notification checks passed")
    }
    func testGraphQLHelpers() {
        precondition(PipelineModel.projectID(fromGraphQL: "gid://gitlab/Project/81197701") == 81197701)
        precondition(PipelineModel.projectID(fromGraphQL: 42) == 42)
        precondition(PipelineModel.normalizeMergeStatus("DRAFT_STATUS") == "draft_status")
        precondition(PipelineModel.normalizeMergeStatus("NOT_APPROVED") == "not_approved")
        precondition(PipelineModel.normalizePipelineStatus("SUCCESS") == "success")
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
        let key = "pipelinetracer.rememberPlace"
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
        precondition(PipelineModel.unresolvedFailures([main, passed, failed]).isEmpty)
        precondition(PipelineModel.unresolvedFailures([failed]).count == 1)
        precondition(PipelineModel.unresolvedFailures([failed, main]).count == 1)
        let olderPass = Pipeline(projectID: 1, id: 9, project: "example/app", ref: "refs/merge-requests/17/head", status: "success", url: "", updated: Date(timeIntervalSince1970: 1), sha: "aaaaaaaaaa")
        precondition(PipelineModel.unresolvedFailures([failed, olderPass]).count == 1)
    }
    func testBranchAndMergeRequestPipelinesGroup() {
        var mr = Pipeline(projectID: 1, id: 20, project: "example/app", ref: "refs/merge-requests/15/head", status: "running", url: "", updated: Date(timeIntervalSince1970: 20), sha: "different-sha")
        mr.sourceBranch = "feature/header"
        let branch = Pipeline(projectID: 1, id: 19, project: "example/app", ref: "feature/header", status: "running", url: "", updated: Date(timeIntervalSince1970: 19), sha: "branch-sha")
        let main = Pipeline(projectID: 1, id: 21, project: "example/app", ref: "main", status: "running", url: "", updated: Date(timeIntervalSince1970: 21), sha: "main-sha")
        let groups = PipelineModel.groupSameChange([main, mr, branch])
        precondition(groups.count == 2)
        precondition(groups.contains { $0.pipelines.map(\.id).sorted() == [19, 20] })
        precondition(groups.contains { $0.pipelines.map(\.id) == [21] })
        precondition(PipelineModel.groupTitle([mr, branch]) == "feature/header")
        precondition(Pipeline(projectID: 1, id: 1, project: "example/app", ref: "refs/merge-requests/15/head", status: "running", url: "", updated: nil).mergeRequestIID == 15)
        precondition(main.mergeRequestIID == nil)
        let sameSha = Pipeline(projectID: 1, id: 30, project: "example/app", ref: "refs/merge-requests/8/head", status: "running", url: "", updated: nil, sha: "abc")
        let twin = Pipeline(projectID: 1, id: 31, project: "example/app", ref: "feature/other", status: "running", url: "", updated: nil, sha: "abc")
        precondition(PipelineModel.groupSameChange([sameSha, twin, main]).count == 2)
        precondition(!PipelineModel.sameChange(sameSha, main))
    }
    func testGitHubRunsStaySeparateFromGitLab() {
        precondition(PipelineModel.githubRepoName("krisrmgua/PipelineTracer") == "krisrmgua/PipelineTracer")
        precondition(PipelineModel.githubRepoName("owner/repo name") == nil)
        precondition(PipelineModel.githubRepoName("owner/repo/extra") == nil)
        precondition(PipelineModel.githubRepoName("https://github.com/owner/repo") == nil)
        precondition(PipelineModel.githubStatus(status: "in_progress", conclusion: nil) == "running")
        precondition(PipelineModel.githubStatus(status: "queued", conclusion: nil) == "pending")
        precondition(PipelineModel.githubStatus(status: "completed", conclusion: "success") == "success")
        precondition(PipelineModel.githubStatus(status: "completed", conclusion: "failure") == "failed")
        precondition(PipelineModel.githubStatus(status: "completed", conclusion: "cancelled") == "canceled")
        precondition(PipelineModel.githubStatus(status: "completed", conclusion: "action_required") == "manual")
        precondition(Shell.browserURL("https://github.com/owner/repo/actions/runs/1")?.host == "github.com")
        precondition(Shell.browserURL("https://gitlab.com/group/repo/-/pipelines/1")?.host == "gitlab.com")
        precondition(Shell.browserURL("http://github.com/owner/repo") == nil)
        precondition(Shell.browserURL("https://evil.github.com.example/owner/repo") == nil)
        let run: [String: Any] = [
            "id": 42, "name": "CI", "head_branch": "main", "head_sha": "abc",
            "status": "completed", "conclusion": "failure",
            "html_url": "https://github.com/example/app/actions/runs/42",
            "updated_at": "2026-11-03T12:00:00Z"
        ]
        let parsed = PipelineModel.parseGitHubRun(run, repoID: 7, repoName: "example/app")
        precondition(parsed?.host == .github)
        precondition(parsed?.status == "failed")
        precondition(parsed?.workflow == "CI")
        precondition(parsed?.refLabel == "CI · main")
        precondition(parsed?.key == "github:7:42")
        let failed = Pipeline(host: .gitlab, projectID: 7, id: 10, project: "example/app", ref: "main", status: "failed", url: "", updated: nil, sha: "abc")
        let passed = Pipeline(host: .github, projectID: 7, id: 99, project: "example/app", ref: "main", status: "success", url: "", updated: nil, sha: "abc", workflow: "CI")
        precondition(PipelineModel.unresolvedFailures([failed, passed]).count == 1)
        precondition(!PipelineModel.sameChange(failed, passed))
        let docs = Pipeline(host: .github, projectID: 7, id: 100, project: "example/app", ref: "main", status: "success", url: "", updated: Date(timeIntervalSince1970: 30), sha: "abc", workflow: "Docs")
        let ci = Pipeline(host: .github, projectID: 7, id: 98, project: "example/app", ref: "main", status: "failed", url: "", updated: Date(timeIntervalSince1970: 20), sha: "abc", workflow: "CI")
        precondition(PipelineModel.unresolvedFailures([docs, ci]).map(\.workflow) == ["CI"])
    }
    func testGitHubPullRequestStatus() {
        let ready = PipelineModel.githubPullStatus(isDraft: false, mergeable: "MERGEABLE", reviewDecision: nil, checks: "SUCCESS")
        precondition(!ready.draft && ready.mergeStatus == "mergeable")
        let review = PipelineModel.githubPullStatus(isDraft: false, mergeable: "MERGEABLE", reviewDecision: "REVIEW_REQUIRED", checks: "SUCCESS")
        precondition(review.mergeStatus == "not_approved")
        let conflict = PipelineModel.githubPullStatus(isDraft: false, mergeable: "CONFLICTING", reviewDecision: nil, checks: nil)
        precondition(conflict.mergeStatus == "conflict")
        let draft = PipelineModel.githubPullStatus(isDraft: true, mergeable: "MERGEABLE", reviewDecision: nil, checks: nil)
        precondition(draft.draft && draft.mergeStatus == "draft_status")
        let node: [String: Any] = [
            "number": 8, "title": "Add login", "url": "https://github.com/example/app/pull/8",
            "isDraft": false, "mergeable": "MERGEABLE", "updatedAt": "2026-11-03T12:00:00Z",
            "headRefName": "feature/login", "baseRefName": "main", "headRefOid": "abc",
            "repository": ["databaseId": 7, "nameWithOwner": "example/app", "isArchived": false],
            "statusCheckRollup": ["state": "SUCCESS"]
        ]
        let parsed = PipelineModel.parseGitHubPull(node)
        precondition(parsed?.host == .github)
        precondition(parsed?.numberLabel == "#8")
        precondition(parsed?.key == "github:7:8")
        precondition(parsed?.isReady == true)
        precondition(parsed?.project == "example/app")
        var badURL = node
        badURL["url"] = "https://example.com/pull/8"
        precondition(PipelineModel.parseGitHubPull(badURL) == nil)
        var archived = node
        archived["repository"] = ["databaseId": 7, "nameWithOwner": "example/app", "isArchived": true]
        precondition(PipelineModel.parseGitHubPull(archived) == nil)
        precondition(PipelineModel.githubMergeMethod(allowMerge: true, allowSquash: true, allowRebase: true) == "merge")
        precondition(PipelineModel.githubMergeMethod(allowMerge: false, allowSquash: true, allowRebase: true) == "squash")
        precondition(PipelineModel.githubMergeMethod(allowMerge: false, allowSquash: false, allowRebase: true) == "rebase")
        precondition(PipelineModel.githubMergeMethod(allowMerge: false, allowSquash: false, allowRebase: false) == nil)
        if case .failed(let message) = PipelineModel.merge(MergeRequest(host: .github, projectID: 7, iid: 8, title: "Add login", project: "not a repo", url: "https://github.com/example/app/pull/8", draft: false, mergeStatus: "mergeable", pipelineStatus: "success", updated: nil)) {
            precondition(message == "couldn't load pull request")
        } else { precondition(false) }
    }
}
