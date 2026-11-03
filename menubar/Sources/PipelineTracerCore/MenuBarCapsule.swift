import AppKit

/// Compact, explicit counters with a shared inset capsule and quiet dividers.
enum MenuBarCapsule {
    static func image(mergeRequests: Int, running: Int, failed: Int,
                      status: PipelineStatus, progress: Double) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let counters: [(String, Int, NSColor)] = [
            ("MR", mergeRequests, .white),
            ("Run", running, .systemCyan),
            ("Fail", failed, .systemRed)
        ]
        let strings = counters.filter { $0.1 > 0 }.map { label, count, color in
            NSAttributedString(string: "\(label) \(count)", attributes: [.font: font, .foregroundColor: color])
        }
        // Fit only visible counters and their dividers; retain balanced ring-only padding.
        let width: CGFloat = strings.isEmpty ? 28 :
            34 + strings.reduce(CGFloat(0)) { $0 + ceil($1.size().width) } + CGFloat(strings.count - 1) * 16
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            let capsule = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            NSColor(calibratedRed: 0.055, green: 0.09, blue: 0.14,
                    alpha: 0.84).setFill()
            capsule.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            capsule.lineWidth = 0.5
            capsule.stroke()
            PipelineProgressRing.image(status: status, progress: progress)
                .draw(in: NSRect(x: 5, y: 2, width: 18, height: 18))
            var x: CGFloat = 28
            for (index, string) in strings.enumerated() {
                string.draw(at: NSPoint(x: x, y: (22 - string.size().height) / 2))
                x += ceil(string.size().width)
                if index < strings.count - 1 {
                    x += 8
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: x, y: 6))
                    divider.line(to: NSPoint(x: x, y: 16))
                    NSColor.white.withAlphaComponent(0.22).setStroke()
                    divider.lineWidth = 0.5
                    divider.stroke()
                    x += 8
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
