import AppKit

/// Overall state of the pipeline the status card shows.
enum PipelineStatus {
    case passed, running, failed, pending, canceled, skipped
}

/// The ring in the menu bar: its color is the pipeline's overall state, and the arc is how
/// many jobs have finished. Drawn with AppKit, so no image assets are needed.
enum PipelineProgressRing {
    private static let done: Set<String> = ["success", "passed", "failed", "canceled", "cancelled", "skipped"]
    private static let waiting: Set<String> = ["pending", "created", "preparing", "waiting_for_resource", "scheduled", "manual"]

    /// Overall state and progress for one pipeline. Failure wins over running, which wins over
    /// waiting. Failed jobs count as finished for progress.
    static func state(for pipeline: Pipeline?) -> (PipelineStatus, Double) {
        guard let p = pipeline else { return (.pending, 0) }
        if ["canceled", "cancelled"].contains(p.status) { return (.canceled, 1) }
        if p.status == "skipped" { return (.skipped, 1) }
        let jobs = p.jobs
        guard !jobs.isEmpty else {
            // No job details yet: fall back to the pipeline's own status.
            switch p.status {
            case "success", "passed": return (.passed, 1)
            case "failed": return (.failed, 1)
            case "running": return (.running, 0)
            default: return (.pending, 0)
            }
        }
        let statuses = jobs.map(\.status)
        let finished = statuses.filter { done.contains($0) }.count
        let progress = Double(finished) / Double(jobs.count)
        if statuses.contains("failed") { return (.failed, progress) }
        if statuses.contains(where: { $0 == "running" }) { return (.running, progress) }
        if statuses.contains(where: { waiting.contains($0) }) { return (.pending, progress) }
        return (.passed, progress)
    }

    static func image(status: PipelineStatus, progress: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5
            let ringRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            let color: NSColor
            switch status {
            case .passed: color = .systemGreen
            case .running: color = .systemOrange
            case .failed: color = .systemRed
            case .canceled, .skipped: color = .systemGray
            case .pending: color = .systemGray   // fixed grey: a label color can vanish on the menu bar
            }

            // Background track in the status color, dimmed.
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = 2.6
            // Track must stay visible on the menu bar, so it is stronger for the grey (no pipeline) state.
            color.withAlphaComponent(status == .pending ? 0.7 : 0.3).setStroke()
            track.stroke()

            // Finished-jobs arc, starting at the top and going clockwise.
            let fraction = min(max(progress, 0), 1)
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.lineWidth = 2.6
                arc.lineCapStyle = .round
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * fraction, clockwise: true)
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
