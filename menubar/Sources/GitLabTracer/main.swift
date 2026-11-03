import AppKit
import GitLabTracerCore

if CommandLine.arguments.contains("--preview") || Bundle.main.bundleIdentifier == "com.kris.gitlabtracer.preview" { Preview.run(); exit(0) }

if CommandLine.arguments.contains("--self-check") { StatusChecks.run(); exit(0) }

if CommandLine.arguments.contains("--dump") {
    Dump.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
