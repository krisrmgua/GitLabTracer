import Foundation

/// Runs a command and returns (exit status, stdout). Uses PATH that includes Homebrew,
/// because `glab` and `git` live there and menubar apps inherit a minimal PATH.
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
}
