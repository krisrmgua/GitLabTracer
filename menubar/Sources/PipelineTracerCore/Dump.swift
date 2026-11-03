import Foundation

/// `PipelineTracer --dump` prints the GitLab data as text, for checking without the menu bar.
public enum Dump {
    public static func run() {
        print("== Merge requests")
        let mrs = PipelineModel.fetchOpenMergeRequests()
        for mr in mrs {
            print("  \(mr.project) !\(mr.iid) [\(mr.pipelineStatus ?? "no pipeline")] \(mr.isReady ? "ready" : mr.mergeStatus) — \(mr.title)")
        }
        print("== Pull requests")
        switch PipelineModel.fetchOpenPullRequests() {
        case .success(let pulls):
            for pr in pulls { print("  github \(pr.project) #\(pr.iid) [\(pr.pipelineStatus ?? "no checks")] \(pr.isReady ? "ready" : pr.mergeStatus) — \(pr.title)") }
        case .failure:
            print("== GitHub pull requests unavailable")
        }
        print("== Pipelines (\(PipelineTracerPrefs.pipelineHours)h)")
        let gitlab = PipelineModel.annotateSourceBranches(PipelineModel.fetchPipelines(hours: PipelineTracerPrefs.pipelineHours), openMRs: mrs)
        let github: [Pipeline]
        switch PipelineModel.fetchGitHubPipelines(hours: PipelineTracerPrefs.pipelineHours) {
        case .success(let list): github = list
        case .failure:
            github = []
            print("== GitHub Actions unavailable")
        }
        var pipes = (gitlab + github).sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        for p in pipes {
            print("  \(p.host.rawValue) \(p.project) #\(p.id) \(p.status) \(p.refLabel)")
        }
        // The card's pipeline and the ring state it gives.
        if let i = pipes.firstIndex(where: { $0.isRunning }) ?? (pipes.isEmpty ? nil : 0) {
            if case .success(let jobs) = PipelineModel.jobsForPipeline(pipes[i]) { pipes[i].jobs = jobs }
            let (status, progress) = PipelineProgressRing.state(for: pipes[i])
            print("== Card pipeline #\(pipes[i].id): \(pipes[i].status), jobs: \(pipes[i].jobs.map { "\($0.name)=\($0.status)" }.joined(separator: ", "))")
            print("== Ring state: \(status), progress \(progress)")
        }
    }
}



