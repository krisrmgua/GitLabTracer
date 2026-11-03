import Foundation

/// `GitLabTracer --dump` prints the GitLab data as text, for checking without the menu bar.
public enum Dump {
    public static func run() {
        print("== Merge requests")
        for mr in GitLabModel.fetchOpenMergeRequests() {
            print("  \(mr.project) !\(mr.iid) [\(mr.pipelineStatus ?? "no pipeline")] \(mr.isReady ? "ready" : mr.mergeStatus) — \(mr.title)")
        }
        print("== Pipelines (\(GitLabTracerPrefs.pipelineHours)h)")
        var pipes = GitLabModel.fetchPipelines(hours: GitLabTracerPrefs.pipelineHours)
        for p in pipes {
            print("  \(p.project) #\(p.id) \(p.status) \(p.ref)")
        }
        // The card's pipeline and the ring state it gives.
        if let i = pipes.firstIndex(where: { $0.isRunning }) ?? (pipes.isEmpty ? nil : 0) {
            pipes[i].jobs = GitLabModel.fetchJobs(projectID: pipes[i].projectID, pipelineID: pipes[i].id)
            let (status, progress) = PipelineProgressRing.state(for: pipes[i])
            print("== Card pipeline #\(pipes[i].id): \(pipes[i].status), jobs: \(pipes[i].jobs.map { "\($0.name)=\($0.status)" }.joined(separator: ", "))")
            print("== Ring state: \(status), progress \(progress)")
        }
    }
}



