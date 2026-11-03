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
        // Taller capsule (~Tickr/TokenPulse stack height) with inset ring so the
        // circle can grow without kissing the top/bottom edge.
        let height: CGFloat = 26
        let padY: CGFloat = 3
        let ringSize = height - padY * 2
        let width: CGFloat = strings.isEmpty ? 32 :
            38 + strings.reduce(CGFloat(0)) { $0 + ceil($1.size().width) } + CGFloat(strings.count - 1) * 16
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let capsule = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            NSColor(calibratedRed: 0.055, green: 0.09, blue: 0.14,
                    alpha: 0.84).setFill()
            capsule.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            capsule.lineWidth = 0.5
            capsule.stroke()
            PipelineProgressRing.image(status: status, progress: progress)
                .draw(in: NSRect(x: 5, y: padY, width: ringSize, height: ringSize))
            var x: CGFloat = 5 + ringSize + 6
            for (index, string) in strings.enumerated() {
                string.draw(at: NSPoint(x: x, y: (height - string.size().height) / 2))
                x += ceil(string.size().width)
                if index < strings.count - 1 {
                    x += 8
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: x, y: padY + 2))
                    divider.line(to: NSPoint(x: x, y: height - padY - 2))
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
