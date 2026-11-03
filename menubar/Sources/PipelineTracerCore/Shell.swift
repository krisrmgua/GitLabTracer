import Foundation

/// Runs a command and returns (exit status, stdout). Uses PATH that includes Homebrew,
/// because `glab`, `gh`, and `git` live there and menubar apps inherit a minimal PATH.
enum Shell {
    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return e
    }()

    @discardableResult
    /// `mergeStderr` puts git's messages (which go to stderr) into the returned text.
    static func run(_ args: [String], cwd: String? = nil, mergeStderr: Bool = false) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.environment = env
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = mergeStderr ? pipe : FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// `glab api <path>` parsed as JSON, or nil on failure.
    static func glabJSON(_ path: String, method: String? = nil) -> Any? {
        var args = ["glab", "api", "--hostname", "gitlab.com"]
        if let method { args += ["-X", method] }
        args.append(path)
        let r = run(args)
        guard r.status == 0, !r.out.isEmpty, let d = r.out.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    /// `glab api graphql -f query=…` parsed as JSON, or nil on failure.
    static func glabGraphQL(_ query: String) -> [String: Any]? {
        let r = run(["glab", "api", "graphql", "--hostname", "gitlab.com", "-f", "query=\(query)"])
        guard r.status == 0, !r.out.isEmpty, let d = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if root["errors"] != nil { return nil }
        return root["data"] as? [String: Any]
    }

    /// `gh api graphql --hostname github.com` data object, or nil on failure.
    static func ghGraphQL(_ query: String) -> [String: Any]? {
        let r = run(["gh", "api", "graphql", "--hostname", "github.com", "-f", "query=\(query)"])
        guard r.status == 0, let d = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if root["errors"] != nil { return nil }
        return root["data"] as? [String: Any]
    }

    /// `gh api --hostname github.com <path>` parsed as JSON. `404` is a missing repo or disabled Actions, not a transport failure.
    static func ghGET(_ path: String) -> (status: Int32, json: Any?) {
        let r = run(["gh", "api", "--hostname", "github.com", path])
        guard let d = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: d) else { return (r.status == 0 ? -1 : r.status, nil) }
        if r.status != 0 {
            let message = (json as? [String: Any])?["message"] as? String
            if message == "Not Found" { return (404, nil) }
            return (r.status, nil)
        }
        return (0, json)
    }

    /// Opens only https://gitlab.com and https://github.com links that came back from the API.
    static func browserURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.user == nil,
              url.host == "gitlab.com" || url.host == "github.com" else { return nil }
        return url
    }
}
