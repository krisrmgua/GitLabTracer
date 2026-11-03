import Foundation

/// An open merge request you created, as shown in the GitLab section.
struct MergeRequest: Equatable {
    let projectID: Int
    let iid: Int
    let title: String
    let project: String       // group/project path
    let url: String
    let draft: Bool
    let mergeStatus: String   // GitLab detailed_merge_status, e.g. "mergeable"
    var pipelineStatus: String?
    let updated: Date?
    var sourceBranch: String = ""
    var targetBranch: String = ""
    var sha: String = ""

    var key: String { "\(projectID):\(iid)" }
    var isReady: Bool { !draft && mergeStatus == "mergeable" }
}

enum GitLabModel {
    static func fetchOpenMergeRequests(onFailure: () -> Void = {}) -> [MergeRequest] {
        guard let list = Shell.glabJSON("merge_requests?scope=created_by_me&state=opened&per_page=30&order_by=updated_at&sort=desc") as? [[String: Any]] else { onFailure(); return [] }
        return list.compactMap(parse)
    }

    static func parse(_ m: [String: Any]) -> MergeRequest? {
        guard let pid = m["project_id"] as? Int,
              let iid = m["iid"] as? Int,
              let title = m["title"] as? String,
              let url = m["web_url"] as? String else { return nil }
        let pipe = (m["head_pipeline"] as? [String: Any])?["status"] as? String
        return MergeRequest(
            projectID: pid, iid: iid, title: title,
            project: projectPath(fromWebURL: url), url: url,
            draft: (m["draft"] as? Bool) ?? false,
            mergeStatus: (m["detailed_merge_status"] as? String) ?? "unknown",
            pipelineStatus: pipe,
            updated: parseDate(m["updated_at"] as? String),
            sourceBranch: m["source_branch"] as? String ?? "",
            targetBranch: m["target_branch"] as? String ?? "",
            sha: m["sha"] as? String ?? ""
        )
    }

    /// "https://gitlab.com/group/proj/-/merge_requests/3" -> "group/proj"
    static func projectPath(fromWebURL url: String) -> String {
        guard let path = URL(string: url)?.path else { return "" }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.components(separatedBy: "/-/").first ?? trimmed
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    enum MergeResult { case merged, failed(String) }

    /// Merges only if GitLab still reports the MR as ready (never trusts the list's stale state).
    static func merge(_ mr: MergeRequest) -> MergeResult {
        guard let fresh = Shell.glabJSON("projects/\(mr.projectID)/merge_requests/\(mr.iid)") as? [String: Any] else {
            return .failed("couldn't load MR")
        }
        let status = (fresh["detailed_merge_status"] as? String) ?? "unknown"
        if (fresh["state"] as? String) != "opened" || (fresh["draft"] as? Bool) == true || status != "mergeable" {
            return .failed("not ready: \(status)")
        }
        guard let sha = fresh["sha"] as? String, !sha.isEmpty else { return .failed("couldn't verify source revision") }
        if !mr.sha.isEmpty && mr.sha != sha { return .failed("source changed since review; refresh and review again") }
        let r = Shell.run(["glab", "api", "--hostname", "gitlab.com", "-X", "PUT",
                           "projects/\(mr.projectID)/merge_requests/\(mr.iid)/merge", "-f", "sha=\(sha)"])
        guard r.status == 0, let d = r.out.data(using: .utf8),
              let res = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (res["state"] as? String) == "merged" else {
            return .failed("merge failed")
        }
        return .merged
    }
}

/// One CI job inside a pipeline.
struct Job: Equatable {
    let id: Int
    let name: String
    let stage: String
    let status: String
    let url: String
    let duration: Double?
}

/// A recent pipeline on one of your projects, with its jobs once loaded.
struct Pipeline {
    let projectID: Int
    let id: Int
    let project: String
    let ref: String
    let status: String
    let url: String
    let updated: Date?
    var sha: String = ""
    var jobs: [Job] = []
    /// Source branch of a merge-request pipeline, when GitLab reported it.
    var sourceBranch: String = ""

    var isRunning: Bool { ["running", "pending", "created", "preparing", "waiting_for_resource", "scheduled"].contains(status) }
    var isFailed: Bool { status == "failed" }
    var isSuccess: Bool { status == "success" || status == "passed" }

    /// `refs/merge-requests/15/head` → 15. Branch and main pipelines are nil.
    var mergeRequestIID: Int? {
        let prefix = "refs/merge-requests/"
        guard ref.hasPrefix(prefix) else { return nil }
        let rest = ref.dropFirst(prefix.count)
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, rest.dropFirst(digits.count) == "/head" else { return nil }
        return Int(digits)
    }
}

/// One card for pipelines that are the same change: the branch run and the
/// merge-request run. `main` stays its own card.
struct PipelineGroup: Identifiable {
    let pipelines: [Pipeline]
    var id: String { pipelines.map { "\($0.projectID):\($0.id)" }.sorted().joined(separator: "|") }
    var primary: Pipeline { pipelines.first(where: { $0.mergeRequestIID != nil }) ?? pipelines[0] }
}

extension GitLabModel {
    /// Newest pipeline for each project and ref.
    static func latestPerRef(_ list: [Pipeline]) -> [Pipeline] {
        var newest: [String: Pipeline] = [:]
        for pipeline in list {
            let key = "\(pipeline.projectID)|\(pipeline.ref)"
            if let current = newest[key], (current.updated ?? .distantPast) >= (pipeline.updated ?? .distantPast) { continue }
            newest[key] = pipeline
        }
        return Array(newest.values)
    }

    /// Failures that are still the latest result for their ref. A later pipeline
    /// for the same commit, such as a merge-request pipeline after the branch
    /// push failed, means that commit is already fixed.
    static func unresolvedFailures(_ list: [Pipeline]) -> [Pipeline] {
        latestPerRef(list).filter { failed in
            guard failed.isFailed else { return false }
            let fixed = list.contains { other in
                other.projectID == failed.projectID
                    && other.id > failed.id
                    && !failed.sha.isEmpty
                    && other.sha == failed.sha
                    && other.isSuccess
            }
            return !fixed
        }
    }

    /// Collapse a merge-request pipeline and the branch pipeline for that same
    /// change into one group. A `main` or `master` pipeline stays separate
    /// unless it is actually the merge request's source branch.
    static func groupSameChange(_ list: [Pipeline]) -> [PipelineGroup] {
        var remaining = list
        var groups: [PipelineGroup] = []
        while !remaining.isEmpty {
            let pipeline = remaining.removeFirst()
            if let match = remaining.firstIndex(where: { other in
                sameChange(pipeline, other)
            }) {
                let other = remaining.remove(at: match)
                let mr = pipeline.mergeRequestIID != nil ? pipeline : other
                let branch = pipeline.mergeRequestIID != nil ? other : pipeline
                groups.append(PipelineGroup(pipelines: [mr, branch]))
            } else {
                groups.append(PipelineGroup(pipelines: [pipeline]))
            }
        }
        return groups
    }

    static func groupTitle(_ pipelines: [Pipeline]) -> String {
        if let branch = pipelines.first(where: { $0.mergeRequestIID == nil }) { return branch.ref }
        if let iid = pipelines.first?.mergeRequestIID { return "MR !\(iid)" }
        return pipelines.first?.ref ?? ""
    }

    static func sameChange(_ lhs: Pipeline, _ rhs: Pipeline) -> Bool {
        guard lhs.projectID == rhs.projectID, lhs.id != rhs.id else { return false }
        let mr = lhs.mergeRequestIID != nil ? lhs : rhs
        let branch = lhs.mergeRequestIID != nil ? rhs : lhs
        guard mr.mergeRequestIID != nil, branch.mergeRequestIID == nil else { return false }
        if !mr.sourceBranch.isEmpty { return branch.ref == mr.sourceBranch }
        if branch.ref == "main" || branch.ref == "master" { return false }
        return !mr.sha.isEmpty && mr.sha == branch.sha
    }
}

extension GitLabModel {
    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func currentUser() -> String? {
        (Shell.glabJSON("user") as? [String: Any])?["username"] as? String
    }

    /// Your recent pipelines across the projects you are a member of (last `hours`).
    static func fetchPipelines(hours: Int = 24, onFailure: @escaping () -> Void = {}) -> [Pipeline] {
        guard let user = currentUser() else { onFailure(); return [] }
        let projectSince = isoString(Date().addingTimeInterval(-3 * 86400))
        guard let projects = Shell.glabJSON("projects?membership=true&archived=false&simple=true&per_page=60&order_by=last_activity_at&sort=desc&last_activity_after=\(projectSince)") as? [[String: Any]] else { onFailure(); return [] }
        let pipeSince = isoString(Date().addingTimeInterval(-Double(hours) * 3600))
        let lock = NSLock()
        var out: [Pipeline] = []
        DispatchQueue.concurrentPerform(iterations: projects.count) { i in
            guard let pid = projects[i]["id"] as? Int,
                  let name = projects[i]["path_with_namespace"] as? String else { return }
            guard let list = Shell.glabJSON("projects/\(pid)/pipelines?username=\(user)&updated_after=\(pipeSince)&per_page=10") as? [[String: Any]] else { onFailure(); return }
            let pipes: [Pipeline] = list.compactMap { d in
                guard let id = d["id"] as? Int, let status = d["status"] as? String,
                      let url = d["web_url"] as? String else { return nil }
                return Pipeline(projectID: pid, id: id, project: name,
                                ref: (d["ref"] as? String) ?? "", status: status, url: url,
                                updated: parseDate(d["updated_at"] as? String),
                                sha: (d["sha"] as? String) ?? "")
            }
            lock.lock(); out += pipes; lock.unlock()
        }
        out = annotateSourceBranches(out)
        return out.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    /// Running merge-request pipelines need the source branch so they can sit
    /// with the branch pipeline even when GitLab gave them different commits.
    private static func annotateSourceBranches(_ pipelines: [Pipeline]) -> [Pipeline] {
        var branches: [String: String] = [:]
        for pipeline in pipelines where pipeline.isRunning {
            guard let iid = pipeline.mergeRequestIID else { continue }
            let key = "\(pipeline.projectID):\(iid)"
            if branches[key] != nil { continue }
            let detail = Shell.glabJSON("projects/\(pipeline.projectID)/merge_requests/\(iid)") as? [String: Any]
            if let branch = detail?["source_branch"] as? String, !branch.isEmpty {
                branches[key] = branch
            }
        }
        return pipelines.map { pipeline in
            guard let iid = pipeline.mergeRequestIID,
                  let branch = branches["\(pipeline.projectID):\(iid)"] else { return pipeline }
            var copy = pipeline
            copy.sourceBranch = branch
            return copy
        }
    }

    static func fetchJobs(projectID: Int, pipelineID: Int) -> [Job] {
        (try? loadJobs(projectID: projectID, pipelineID: pipelineID).get()) ?? []
    }

    enum LoadError: Error { case unavailable }
    static func loadJobs(projectID: Int, pipelineID: Int) -> Result<[Job], LoadError> {
        guard let list = Shell.glabJSON("projects/\(projectID)/pipelines/\(pipelineID)/jobs?per_page=100") as? [[String: Any]] else { return .failure(.unavailable) }
        // GitLab lists jobs newest first. Sort by id (creation order) so stages and jobs read top to bottom.
        let jobs: [Job] = list.compactMap { d in
            guard let id = d["id"] as? Int, let name = d["name"] as? String,
                  let status = d["status"] as? String else { return nil }
            return Job(id: id, name: name, stage: (d["stage"] as? String) ?? "",
                       status: status, url: (d["web_url"] as? String) ?? "",
                       duration: d["duration"] as? Double)
        }.sorted { $0.id < $1.id }
        return .success(jobs)
    }
}
