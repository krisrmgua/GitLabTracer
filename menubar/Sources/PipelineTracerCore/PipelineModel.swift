import Foundation

/// An open GitLab merge request or GitHub pull request you created.
struct MergeRequest: Equatable {
    var host: PipelineHost = .gitlab
    let projectID: Int
    let iid: Int
    let title: String
    let project: String       // group/project or owner/repo
    let url: String
    let draft: Bool
    let mergeStatus: String   // GitLab detailed_merge_status, or the same words for a GitHub pull request
    var pipelineStatus: String?
    let updated: Date?
    var sourceBranch: String = ""
    var targetBranch: String = ""
    var sha: String = ""

    var key: String { host == .github ? "github:\(projectID):\(iid)" : "\(projectID):\(iid)" }
    var numberLabel: String { host == .github ? "#\(iid)" : "!\(iid)" }
    var isReady: Bool { !draft && mergeStatus == "mergeable" }
}

enum PipelineModel {
    private static let cacheLock = NSLock()
    private static var cachedUsername: String?
    private static var cachedUsernameAt: Date?
    /// Jobs keyed by `projectID:pipelineID`, kept while status+sha stay the same.
    private static var jobCache: [String: (fingerprint: String, jobs: [Job])] = [:]
    private static let usernameTTL: TimeInterval = 3600

    /// One GraphQL query: open MRs you authored, with archived project flag inlined.
    static func fetchOpenMergeRequests(onFailure: () -> Void = {}) -> [MergeRequest] {
        let query = """
        query{currentUser{authoredMergeRequests(state:opened,first:30,sort:UPDATED_DESC){nodes{iid title webUrl draft detailedMergeStatus sourceBranch targetBranch diffHeadSha updatedAt project{id fullPath archived} headPipeline{status}}}}}
        """
        guard let data = Shell.glabGraphQL(query),
              let user = data["currentUser"] as? [String: Any],
              let connection = user["authoredMergeRequests"] as? [String: Any],
              let nodes = connection["nodes"] as? [[String: Any]] else {
            // REST fallback if GraphQL is unavailable.
            return fetchOpenMergeRequestsREST(onFailure: onFailure)
        }
        // parseGraphQL drops archived projects.
        return nodes.compactMap(parseGraphQL)
    }

    /// REST path kept as fallback; still avoids N archived lookups via a short-lived cache.
    private static func fetchOpenMergeRequestsREST(onFailure: () -> Void) -> [MergeRequest] {
        guard let list = Shell.glabJSON("merge_requests?scope=created_by_me&state=opened&per_page=30&order_by=updated_at&sort=desc") as? [[String: Any]] else {
            onFailure(); return []
        }
        let mrs = list.compactMap(parse)
        let archived = archivedProjects(Set(mrs.map(\.projectID)))
        return mrs.filter { !archived.contains($0.projectID) }
    }

    /// Project IDs among `ids` that GitLab reports as archived (cached).
    static func archivedProjects(_ ids: Set<Int>) -> Set<Int> {
        guard !ids.isEmpty else { return [] }
        cacheLock.lock()
        var known = archivedCache
        cacheLock.unlock()
        var archived = Set<Int>()
        var missing: [Int] = []
        for id in ids {
            if let cached = known[id] {
                if cached { archived.insert(id) }
            } else {
                missing.append(id)
            }
        }
        for id in missing {
            let isArchived = (Shell.glabJSON("projects/\(id)?simple=true") as? [String: Any])?["archived"] as? Bool ?? false
            known[id] = isArchived
            if isArchived { archived.insert(id) }
        }
        cacheLock.lock()
        archivedCache = known
        cacheLock.unlock()
        return archived
    }

    private static var archivedCache: [Int: Bool] = [:]

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
            mergeStatus: normalizeMergeStatus(m["detailed_merge_status"] as? String),
            pipelineStatus: pipe.map(normalizePipelineStatus),
            updated: parseDate(m["updated_at"] as? String),
            sourceBranch: m["source_branch"] as? String ?? "",
            targetBranch: m["target_branch"] as? String ?? "",
            sha: m["sha"] as? String ?? ""
        )
    }

    static func parseGraphQL(_ node: [String: Any]) -> MergeRequest? {
        guard let project = node["project"] as? [String: Any],
              (project["archived"] as? Bool) != true,
              let pid = projectID(fromGraphQL: project["id"]),
              let path = project["fullPath"] as? String,
              let iidValue = node["iid"],
              let iid = Int("\(iidValue)"),
              let title = node["title"] as? String,
              let url = node["webUrl"] as? String else { return nil }
        let pipe = (node["headPipeline"] as? [String: Any])?["status"] as? String
        return MergeRequest(
            projectID: pid, iid: iid, title: title,
            project: path, url: url,
            draft: (node["draft"] as? Bool) ?? false,
            mergeStatus: normalizeMergeStatus(node["detailedMergeStatus"] as? String),
            pipelineStatus: pipe.map(normalizePipelineStatus),
            updated: parseDate(node["updatedAt"] as? String),
            sourceBranch: node["sourceBranch"] as? String ?? "",
            targetBranch: node["targetBranch"] as? String ?? "",
            sha: node["diffHeadSha"] as? String ?? ""
        )
    }

    /// `gid://gitlab/Project/123` → 123
    static func projectID(fromGraphQL value: Any?) -> Int? {
        if let n = value as? Int { return n }
        guard let s = value as? String else { return nil }
        if let n = Int(s) { return n }
        return Int(s.split(separator: "/").last.map(String.init) ?? "")
    }

    static func normalizeMergeStatus(_ raw: String?) -> String {
        (raw ?? "unknown").replacingOccurrences(of: " ", with: "_").lowercased()
    }

    static func normalizePipelineStatus(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "_").lowercased()
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
    enum CloseResult { case closed, failed(String) }

    /// Merges only if the host still reports the request as ready (never trusts the list's stale state).
    static func merge(_ mr: MergeRequest) -> MergeResult {
        if mr.host == .github { return mergeGitHub(mr) }
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

    /// Closes an open request after re-checking the host. Does not delete the source branch.
    static func close(_ mr: MergeRequest) -> CloseResult {
        if mr.host == .github { return closeGitHub(mr) }
        guard let fresh = Shell.glabJSON("projects/\(mr.projectID)/merge_requests/\(mr.iid)") as? [String: Any] else {
            return .failed("couldn't load MR")
        }
        guard (fresh["state"] as? String) == "opened" else {
            return .failed("already \((fresh["state"] as? String) ?? "unavailable")")
        }
        let r = Shell.run(["glab", "api", "--hostname", "gitlab.com", "-X", "PUT",
                           "projects/\(mr.projectID)/merge_requests/\(mr.iid)", "-f", "state_event=close"])
        guard r.status == 0, let d = r.out.data(using: .utf8),
              let res = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (res["state"] as? String) == "closed" else {
            return .failed("close failed")
        }
        return .closed
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

enum PipelineHost: String { case gitlab, github }

/// A recent pipeline on one of your projects, with its jobs once loaded.
struct Pipeline {
    var host: PipelineHost = .gitlab
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
    /// GitHub workflow name. Empty for GitLab.
    var workflow: String = ""

    var key: String { "\(host.rawValue):\(projectID):\(id)" }
    var refLabel: String {
        guard host == .github, !workflow.isEmpty else { return ref }
        return ref.isEmpty ? workflow : "\(workflow) · \(ref)"
    }
    var serviceName: String { host == .github ? "GitHub" : "GitLab" }

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
    var id: String { pipelines.map(\.key).sorted().joined(separator: "|") }
    var primary: Pipeline { pipelines.first(where: { $0.mergeRequestIID != nil }) ?? pipelines[0] }
}

extension PipelineModel {
    /// Newest pipeline for each project and ref.
    static func latestPerRef(_ list: [Pipeline]) -> [Pipeline] {
        var newest: [String: Pipeline] = [:]
        for pipeline in list {
            let key = pipeline.host == .github
                ? "github|\(pipeline.projectID)|\(pipeline.workflow)|\(pipeline.ref)"
                : "gitlab|\(pipeline.projectID)|\(pipeline.ref)"
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
                other.host == failed.host
                    && other.projectID == failed.projectID
                    && other.id > failed.id
                    && !failed.sha.isEmpty
                    && other.sha == failed.sha
                    && other.isSuccess
                    && (failed.host != .github || other.workflow == failed.workflow)
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
        guard lhs.host == rhs.host, lhs.projectID == rhs.projectID, lhs.id != rhs.id else { return false }
        let mr = lhs.mergeRequestIID != nil ? lhs : rhs
        let branch = lhs.mergeRequestIID != nil ? rhs : lhs
        guard mr.mergeRequestIID != nil, branch.mergeRequestIID == nil else { return false }
        if !mr.sourceBranch.isEmpty { return branch.ref == mr.sourceBranch }
        if branch.ref == "main" || branch.ref == "master" { return false }
        return !mr.sha.isEmpty && mr.sha == branch.sha
    }
}

extension PipelineModel {
    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Cached for an hour so the timer does not burn a call every tick.
    static func currentUser() -> String? {
        cacheLock.lock()
        if let name = cachedUsername, let at = cachedUsernameAt, Date().timeIntervalSince(at) < usernameTTL {
            cacheLock.unlock()
            return name
        }
        cacheLock.unlock()
        let name = (Shell.glabJSON("user") as? [String: Any])?["username"] as? String
        if let name {
            cacheLock.lock()
            cachedUsername = name
            cachedUsernameAt = Date()
            cacheLock.unlock()
        }
        return name
    }

    /// Your recent pipelines in one (or a few) instance-level calls instead of one per project.
    static func fetchPipelines(hours: Int = 24, onFailure: @escaping () -> Void = {}) -> [Pipeline] {
        guard currentUser() != nil else { onFailure(); return [] }
        let since = Date().addingTimeInterval(-Double(hours) * 3600)
        // Instance endpoint filters by created_at; keep a little slack then keep rows by updated_at.
        let createdAfter = isoString(since.addingTimeInterval(-6 * 3600))
        let path = "pipelines?per_page=100&order_by=created_at&sort=desc&created_after=\(createdAfter)"
        guard let list = Shell.glabJSON(path) as? [[String: Any]] else { onFailure(); return [] }
        let out: [Pipeline] = list.compactMap { d in
            guard let pipe = parseInstancePipeline(d) else { return nil }
            if let updated = pipe.updated, updated < since { return nil }
            return pipe
        }
        return out.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    static func parseInstancePipeline(_ d: [String: Any]) -> Pipeline? {
        guard let id = d["id"] as? Int,
              let status = d["status"] as? String,
              let url = d["web_url"] as? String else { return nil }
        let project = d["project"] as? [String: Any]
        let pid = (d["project_id"] as? Int) ?? (project?["id"] as? Int)
        guard let pid else { return nil }
        let name = (project?["path_with_namespace"] as? String)
            ?? projectPath(fromWebURL: url)
        return Pipeline(
            projectID: pid, id: id, project: name,
            ref: (d["ref"] as? String) ?? "", status: status, url: url,
            updated: parseDate(d["updated_at"] as? String) ?? parseDate(d["created_at"] as? String),
            sha: (d["sha"] as? String) ?? ""
        )
    }

    /// Prefer source branches already loaded with open MRs; only hit the API for the rest.
    static func annotateSourceBranches(_ pipelines: [Pipeline], openMRs: [MergeRequest] = []) -> [Pipeline] {
        var branches: [String: String] = [:]
        for mr in openMRs where mr.host == .gitlab && !mr.sourceBranch.isEmpty {
            branches["\(mr.projectID):\(mr.iid)"] = mr.sourceBranch
        }
        for pipeline in pipelines where pipeline.host == .gitlab && pipeline.isRunning {
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

    /// Reuse jobs while the pipeline status and SHA are unchanged.
    static func cachedJobs(host: PipelineHost = .gitlab, projectID: Int, pipelineID: Int, status: String, sha: String) -> [Job]? {
        let key = "\(host.rawValue):\(projectID):\(pipelineID)"
        let fingerprint = "\(status)|\(sha)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let hit = jobCache[key], hit.fingerprint == fingerprint else { return nil }
        return hit.jobs
    }

    static func storeJobs(_ jobs: [Job], host: PipelineHost = .gitlab, projectID: Int, pipelineID: Int, status: String, sha: String) {
        let key = "\(host.rawValue):\(projectID):\(pipelineID)"
        cacheLock.lock()
        jobCache[key] = (fingerprint: "\(status)|\(sha)", jobs: jobs)
        cacheLock.unlock()
    }

    static func jobsForPipeline(_ pipeline: Pipeline, force: Bool = false) -> Result<[Job], LoadError> {
        if !force, let cached = cachedJobs(host: pipeline.host, projectID: pipeline.projectID, pipelineID: pipeline.id, status: pipeline.status, sha: pipeline.sha) {
            return .success(cached)
        }
        let result = loadJobs(pipeline)
        if case .success(let jobs) = result {
            storeJobs(jobs, host: pipeline.host, projectID: pipeline.projectID, pipelineID: pipeline.id, status: pipeline.status, sha: pipeline.sha)
        }
        return result
    }

    enum LoadError: Error { case unavailable }
    static func loadJobs(projectID: Int, pipelineID: Int) -> Result<[Job], LoadError> {
        loadJobs(Pipeline(projectID: projectID, id: pipelineID, project: "", ref: "", status: "", url: "", updated: nil))
    }

    static func loadJobs(_ pipeline: Pipeline) -> Result<[Job], LoadError> {
        if pipeline.host == .github { return loadGitHubJobs(pipeline) }
        guard let list = Shell.glabJSON("projects/\(pipeline.projectID)/pipelines/\(pipeline.id)/jobs?per_page=100") as? [[String: Any]] else { return .failure(.unavailable) }
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

extension PipelineModel {
    private static var githubLoginCache: String?
    private static var githubLoginAt: Date?
    private static var githubRepoCache: [GitHubRepo] = []
    private static var githubRepoCacheAt: Date?
    private static let githubRepoTTL: TimeInterval = 600

    struct GitHubRepo {
        let id: Int
        let name: String
        let pushed: Date?
    }

    /// `owner/repo` with the characters GitHub allows in those two parts. Anything else is rejected before it reaches `gh`.
    static func githubRepoName(_ name: String) -> String? {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let allowed: (Substring) -> Bool = { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        }
        guard allowed(parts[0]), allowed(parts[1]) else { return nil }
        return name
    }

    static func jsonInt(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber, n.doubleValue.rounded() == n.doubleValue { return n.intValue }
        return nil
    }

    /// Maps a workflow run onto the statuses the panel already uses.
    static func githubStatus(status: String, conclusion: String?) -> String {
        switch status {
        case "queued", "requested", "pending": return "pending"
        case "in_progress": return "running"
        case "waiting": return "manual"
        case "completed":
            switch conclusion ?? "" {
            case "success", "neutral": return "success"
            case "failure", "timed_out", "startup_failure": return "failed"
            case "cancelled": return "canceled"
            case "skipped", "stale": return "skipped"
            case "action_required": return "manual"
            default: return "failed"
            }
        default: return "pending"
        }
    }

    static func githubLogin() -> String? {
        cacheLock.lock()
        if let name = githubLoginCache, let at = githubLoginAt, Date().timeIntervalSince(at) < usernameTTL {
            cacheLock.unlock()
            return name
        }
        cacheLock.unlock()
        let response = Shell.ghGET("user")
        let name = (response.json as? [String: Any])?["login"] as? String
        guard response.status == 0, let name, !name.isEmpty else { return nil }
        cacheLock.lock()
        githubLoginCache = name
        githubLoginAt = Date()
        cacheLock.unlock()
        return name
    }

    /// Recently pushed repos, cached for 10 minutes. There is no single "my workflow runs" API.
    static func githubRepos() -> Result<[GitHubRepo], LoadError> {
        cacheLock.lock()
        if let at = githubRepoCacheAt, Date().timeIntervalSince(at) < githubRepoTTL {
            let cached = githubRepoCache
            cacheLock.unlock()
            return .success(cached)
        }
        cacheLock.unlock()
        let response = Shell.ghGET("user/repos?per_page=30&sort=pushed&direction=desc&affiliation=owner,collaborator,organization_member")
        guard response.status == 0, let list = response.json as? [[String: Any]] else { return .failure(.unavailable) }
        let repos: [GitHubRepo] = list.compactMap { item in
            guard (item["archived"] as? Bool) != true,
                  let id = jsonInt(item["id"]),
                  let name = githubRepoName(item["full_name"] as? String ?? "") else { return nil }
            return GitHubRepo(id: id, name: name, pushed: parseDate(item["pushed_at"] as? String))
        }
        cacheLock.lock()
        githubRepoCache = repos
        githubRepoCacheAt = Date()
        cacheLock.unlock()
        return .success(repos)
    }

    /// Repos pushed inside the window, capped at 12. If none were, the 8 most recently pushed repos are checked so a quiet day still shows the latest run.
    static func githubRepos(hours: Int) -> Result<[GitHubRepo], LoadError> {
        switch githubRepos() {
        case .failure(let error): return .failure(error)
        case .success(let all):
            let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
            let recent = all.filter { ($0.pushed ?? .distantPast) >= cutoff }
            let picked = recent.isEmpty ? Array(all.prefix(8)) : Array(recent.prefix(12))
            return .success(picked)
        }
    }

    static func fetchGitHubPipelines(hours: Int = 24) -> Result<[Pipeline], LoadError> {
        guard githubLogin() != nil else { return .failure(.unavailable) }
        let repos: [GitHubRepo]
        switch githubRepos(hours: hours) {
        case .failure(let error): return .failure(error)
        case .success(let list): repos = list
        }
        let since = Date().addingTimeInterval(-Double(hours) * 3600)
        var out: [Pipeline] = []
        var sawRuns = false
        var sawFailure = false
        for repo in repos {
            let response = Shell.ghGET("repos/\(repo.name)/actions/runs?per_page=20")
            if response.status == 404 { sawRuns = true; continue }
            guard response.status == 0, let body = response.json as? [String: Any],
                  let runs = body["workflow_runs"] as? [[String: Any]] else {
                sawFailure = true
                continue
            }
            sawRuns = true
            for run in runs {
                guard let pipe = parseGitHubRun(run, repoID: repo.id, repoName: repo.name) else { continue }
                if let updated = pipe.updated, updated < since { continue }
                out.append(pipe)
            }
        }
        if !sawRuns && sawFailure { return .failure(.unavailable) }
        return .success(out.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) })
    }

    static func parseGitHubRun(_ run: [String: Any], repoID: Int, repoName: String) -> Pipeline? {
        guard githubRepoName(repoName) != nil,
              let id = jsonInt(run["id"]),
              let url = run["html_url"] as? String, url.hasPrefix("https://github.com/"),
              let status = run["status"] as? String else { return nil }
        let branch = run["head_branch"] as? String ?? ""
        return Pipeline(
            host: .github, projectID: repoID, id: id, project: repoName, ref: branch,
            status: githubStatus(status: status, conclusion: run["conclusion"] as? String),
            url: url,
            updated: parseDate(run["updated_at"] as? String) ?? parseDate(run["created_at"] as? String),
            sha: run["head_sha"] as? String ?? "",
            workflow: run["name"] as? String ?? ""
        )
    }

    static func loadGitHubJobs(_ pipeline: Pipeline) -> Result<[Job], LoadError> {
        guard let repo = githubRepoName(pipeline.project) else { return .failure(.unavailable) }
        let response = Shell.ghGET("repos/\(repo)/actions/runs/\(pipeline.id)/jobs?per_page=100")
        guard response.status == 0, let body = response.json as? [String: Any],
              let list = body["jobs"] as? [[String: Any]] else { return .failure(.unavailable) }
        let jobs: [Job] = list.compactMap { item in
            guard let id = jsonInt(item["id"]), let name = item["name"] as? String else { return nil }
            let status = githubStatus(status: item["status"] as? String ?? "", conclusion: item["conclusion"] as? String)
            let start = parseDate(item["started_at"] as? String)
            let end = parseDate(item["completed_at"] as? String)
            let duration: Double? = {
                guard let start, let end, end >= start else { return nil }
                return end.timeIntervalSince(start)
            }()
            let url = (item["html_url"] as? String).flatMap { $0.hasPrefix("https://github.com/") ? $0 : nil } ?? ""
            return Job(id: id, name: name, stage: name, status: status, url: url, duration: duration)
        }.sorted { $0.id < $1.id }
        return .success(jobs)
    }

    struct GitHubPullStatus {
        let draft: Bool
        let mergeStatus: String
        let pipeline: String?
    }

    /// First method the repo allows, in GitHub's API order: merge, squash, rebase.
    static func githubMergeMethod(allowMerge: Bool, allowSquash: Bool, allowRebase: Bool) -> String? {
        if allowMerge { return "merge" }
        if allowSquash { return "squash" }
        if allowRebase { return "rebase" }
        return nil
    }

    /// Maps GitHub's mergeable, review, and check rollup onto the words the request row already uses.
    static func githubPullStatus(isDraft: Bool, mergeable: String?, reviewDecision: String?, checks: String?) -> GitHubPullStatus {
        let pipeline: String? = {
            switch checks {
            case "SUCCESS": return "success"
            case "FAILURE", "ERROR": return "failed"
            case "PENDING", "EXPECTED": return "running"
            default: return nil
            }
        }()
        if isDraft { return GitHubPullStatus(draft: true, mergeStatus: "draft_status", pipeline: pipeline) }
        switch mergeable {
        case "CONFLICTING":
            return GitHubPullStatus(draft: false, mergeStatus: "conflict", pipeline: pipeline)
        case "MERGEABLE":
            if reviewDecision == "CHANGES_REQUESTED" { return GitHubPullStatus(draft: false, mergeStatus: "requested_changes", pipeline: pipeline) }
            if reviewDecision == "REVIEW_REQUIRED" { return GitHubPullStatus(draft: false, mergeStatus: "not_approved", pipeline: pipeline) }
            if pipeline == "failed" { return GitHubPullStatus(draft: false, mergeStatus: "ci_must_pass", pipeline: pipeline) }
            if pipeline == "running" { return GitHubPullStatus(draft: false, mergeStatus: "ci_still_running", pipeline: pipeline) }
            return GitHubPullStatus(draft: false, mergeStatus: "mergeable", pipeline: pipeline ?? "success")
        default:
            return GitHubPullStatus(draft: false, mergeStatus: "checking", pipeline: pipeline)
        }
    }

    /// Open pull requests you created. One GraphQL call, up to 30, newest update first.
    static func fetchOpenPullRequests() -> Result<[MergeRequest], LoadError> {
        guard githubLogin() != nil else { return .failure(.unavailable) }
        let query = "query{viewer{pullRequests(states:OPEN,first:30,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number title url isDraft mergeable reviewDecision updatedAt headRefName baseRefName headRefOid repository{databaseId nameWithOwner isArchived}statusCheckRollup{state}}}}}"
        guard let data = Shell.ghGraphQL(query),
              let viewer = data["viewer"] as? [String: Any],
              let connection = viewer["pullRequests"] as? [String: Any],
              let nodes = connection["nodes"] as? [[String: Any]] else { return .failure(.unavailable) }
        return .success(nodes.compactMap(parseGitHubPull))
    }

    static func parseGitHubPull(_ node: [String: Any]) -> MergeRequest? {
        guard let repo = node["repository"] as? [String: Any],
              (repo["isArchived"] as? Bool) != true,
              let name = githubRepoName(repo["nameWithOwner"] as? String ?? ""),
              let pid = jsonInt(repo["databaseId"]),
              let iid = jsonInt(node["number"]),
              let title = node["title"] as? String,
              let url = node["url"] as? String, url.hasPrefix("https://github.com/") else { return nil }
        let checks = (node["statusCheckRollup"] as? [String: Any])?["state"] as? String
        let mapped = githubPullStatus(isDraft: (node["isDraft"] as? Bool) ?? false, mergeable: node["mergeable"] as? String, reviewDecision: node["reviewDecision"] as? String, checks: checks)
        return MergeRequest(
            host: .github, projectID: pid, iid: iid, title: title, project: name, url: url,
            draft: mapped.draft, mergeStatus: mapped.mergeStatus, pipelineStatus: mapped.pipeline,
            updated: parseDate(node["updatedAt"] as? String),
            sourceBranch: node["headRefName"] as? String ?? "",
            targetBranch: node["baseRefName"] as? String ?? "",
            sha: node["headRefOid"] as? String ?? ""
        )
    }

    /// Reloads one pull request and its check runs. Does not merge or close it.
    static func githubPullDetail(_ mr: MergeRequest) -> (request: MergeRequest, body: String, author: String, jobs: [Job])? {
        guard mr.host == .github, let repo = githubRepoName(mr.project) else { return nil }
        let response = Shell.ghGET("repos/\(repo)/pulls/\(mr.iid)")
        guard response.status == 0, let item = response.json as? [String: Any],
              let title = item["title"] as? String,
              let url = item["html_url"] as? String, url.hasPrefix("https://github.com/") else { return nil }
        let head = item["head"] as? [String: Any]
        let base = item["base"] as? [String: Any]
        let sha = head?["sha"] as? String ?? ""
        let jobs = githubCheckJobs(repo: repo, sha: sha)
        let draft = (item["draft"] as? Bool) ?? false
        let mergeable = item["mergeable"] as? Bool
        let state = item["mergeable_state"] as? String
        let failed = jobs.contains { $0.status == "failed" }
        let running = jobs.contains { ["running", "pending", "manual"].contains($0.status) }
        let mergeStatus: String = {
            if draft { return "draft_status" }
            if mergeable == nil { return "checking" }
            if mergeable == false {
                if state == "dirty" { return "conflict" }
                return "blocked_status"
            }
            if state == "behind" { return "behind" }
            if failed { return "ci_must_pass" }
            if running || state == "unstable" { return "ci_still_running" }
            return "mergeable"
        }()
        let pipeline: String? = failed ? "failed" : running ? "running" : jobs.isEmpty ? nil : "success"
        let fresh = MergeRequest(
            host: .github, projectID: mr.projectID, iid: mr.iid, title: title, project: repo, url: url,
            draft: draft, mergeStatus: mergeStatus, pipelineStatus: pipeline,
            updated: parseDate(item["updated_at"] as? String),
            sourceBranch: head?["ref"] as? String ?? "",
            targetBranch: base?["ref"] as? String ?? "",
            sha: sha
        )
        let author = (item["user"] as? [String: Any])?["login"] as? String ?? ""
        return (fresh, item["body"] as? String ?? "", author, jobs)
    }

    /// Merges only when GitHub still says the pull request is open, not a draft, and clean, and the head SHA is unchanged.
    static func mergeGitHub(_ mr: MergeRequest) -> MergeResult {
        guard let repo = githubRepoName(mr.project) else { return .failed("couldn't load pull request") }
        let response = Shell.ghGET("repos/\(repo)/pulls/\(mr.iid)")
        guard response.status == 0, let fresh = response.json as? [String: Any] else { return .failed("couldn't load pull request") }
        let mergeableState = fresh["mergeable_state"] as? String ?? "unknown"
        if (fresh["state"] as? String) != "open" || (fresh["draft"] as? Bool) == true || (fresh["mergeable"] as? Bool) != true || mergeableState != "clean" {
            return .failed("not ready: \(mergeableState)")
        }
        guard let sha = (fresh["head"] as? [String: Any])?["sha"] as? String, !sha.isEmpty, sha.allSatisfy(\.isHexDigit) else {
            return .failed("couldn't verify source revision")
        }
        if !mr.sha.isEmpty && mr.sha != sha { return .failed("source changed since review; refresh and review again") }
        let settings = (fresh["base"] as? [String: Any])?["repo"] as? [String: Any]
        guard let method = githubMergeMethod(
            allowMerge: (settings?["allow_merge_commit"] as? Bool) ?? true,
            allowSquash: (settings?["allow_squash_merge"] as? Bool) ?? false,
            allowRebase: (settings?["allow_rebase_merge"] as? Bool) ?? false
        ) else { return .failed("this repo does not allow merges") }
        let result = Shell.run(["gh", "api", "--hostname", "github.com", "--method", "PUT",
                                "repos/\(repo)/pulls/\(mr.iid)/merge", "-f", "sha=\(sha)", "-f", "merge_method=\(method)"])
        guard result.status == 0, let data = result.out.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (body["merged"] as? Bool) == true else { return .failed("merge failed") }
        return .merged
    }

    /// Closes an open pull request. Does not delete the source branch.
    static func closeGitHub(_ mr: MergeRequest) -> CloseResult {
        guard let repo = githubRepoName(mr.project) else { return .failed("couldn't load pull request") }
        let response = Shell.ghGET("repos/\(repo)/pulls/\(mr.iid)")
        guard response.status == 0, let fresh = response.json as? [String: Any] else { return .failed("couldn't load pull request") }
        guard (fresh["state"] as? String) == "open" else {
            return .failed("already \((fresh["state"] as? String) ?? "unavailable")")
        }
        let result = Shell.run(["gh", "api", "--hostname", "github.com", "--method", "PATCH",
                                "repos/\(repo)/pulls/\(mr.iid)", "-f", "state=closed"])
        guard result.status == 0, let data = result.out.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (body["state"] as? String) == "closed" else { return .failed("close failed") }
        return .closed
    }

    static func githubCheckJobs(repo: String, sha: String) -> [Job] {
        guard githubRepoName(repo) != nil, !sha.isEmpty, sha.allSatisfy({ $0.isHexDigit }) else { return [] }
        let response = Shell.ghGET("repos/\(repo)/commits/\(sha)/check-runs?per_page=100")
        guard response.status == 0, let body = response.json as? [String: Any],
              let list = body["check_runs"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = jsonInt(item["id"]), let name = item["name"] as? String else { return nil }
            let status = githubStatus(status: item["status"] as? String ?? "", conclusion: item["conclusion"] as? String)
            let start = parseDate(item["started_at"] as? String)
            let end = parseDate(item["completed_at"] as? String)
            let duration: Double? = {
                guard let start, let end, end >= start else { return nil }
                return end.timeIntervalSince(start)
            }()
            let url = (item["html_url"] as? String).flatMap { $0.hasPrefix("https://github.com/") ? $0 : nil } ?? ""
            return Job(id: id, name: name, stage: name, status: status, url: url, duration: duration)
        }.sorted { $0.id < $1.id }
    }

    enum JobTrace { case text(String), unavailable }

    /// GitLab returns a text trace. GitHub's job-log endpoint returns text; a zip is left for the browser.
    static func jobTrace(job: Job, pipeline: Pipeline) -> JobTrace {
        switch pipeline.host {
        case .gitlab:
            let result = Shell.run(["glab", "api", "--hostname", "gitlab.com", "projects/\(pipeline.projectID)/jobs/\(job.id)/trace"])
            return result.status == 0 ? .text(result.out) : .unavailable
        case .github:
            guard let repo = githubRepoName(pipeline.project) else { return .unavailable }
            let result = Shell.run(["gh", "api", "--hostname", "github.com", "repos/\(repo)/actions/jobs/\(job.id)/logs"])
            guard result.status == 0 else { return .unavailable }
            if result.out.hasPrefix("PK\u{3}\u{4}") { return .unavailable }
            return .text(result.out)
        }
    }
}
