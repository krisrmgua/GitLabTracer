import AppKit

/// The status card at the top of the dropdown: overall state, stage timeline, job rows,
/// and a link to the pipeline. Presentation only; it reads a `Pipeline` from GitLabModel.
enum PipelineCard {
    static let width: CGFloat = 330

    static func view(for pipeline: Pipeline?, summary: String, openURL: @escaping (String) -> Void) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width   // rows stretch to the card's width, which follows the menu's width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 0, right: 14)   // the menu's own row padding follows
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let p = pipeline else {
            stack.addArrangedSubview(label("No recent pipelines", size: 12, color: .secondaryLabelColor))
            stack.addArrangedSubview(divider())
            stack.addArrangedSubview(leftAligned(countsLabel(summary)))
            return wrap(stack)
        }

        stack.addArrangedSubview(overall(p) { openURL(p.url) })
        let stages = timeline(p)
        stack.addArrangedSubview(stages)
        stack.setCustomSpacing(6, after: stages)   // tight gap between the stage row and the divider below
        // The timeline already shows passed stages, so list only the jobs that still need attention.
        let open = p.jobs.filter { $0.status != "success" && $0.status != "passed" }
        if !open.isEmpty {
            stack.addArrangedSubview(divider())
            stack.addArrangedSubview(label("JOBS", size: 10, bold: true, color: .secondaryLabelColor))
            for job in open { stack.addArrangedSubview(jobRow(job)) }
        }
        // The divider and the counts line belong to the card, so its spacing is set here.
        let rule = divider()
        stack.addArrangedSubview(rule)
        stack.setCustomSpacing(4, after: rule)   // a little space between the divider and the counts line
        stack.addArrangedSubview(leftAligned(countsLabel(summary)))
        return wrap(stack)
    }

    /// Menu items take a view with a fixed frame: pin the stack to its edges, then size the
    /// frame to the stack's laid-out height.
    private static func wrap(_ stack: NSStackView) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        root.autoresizingMask = [.width]
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        root.layoutSubtreeIfNeeded()
        root.frame.size.height = stack.fittingSize.height
        root.layoutSubtreeIfNeeded()
        return root
    }

    /// Icon and status on the left. The title sits at the left of the text column, and the browser
    /// link is pinned to the right edge of that same line. Detail lines stay left-aligned below.
    private static func overall(_ p: Pipeline, open: @escaping () -> Void) -> NSView {
        let (symbolName, color, title) = overallStyle(p)
        let icon = symbol(symbolName, size: 30, color: color)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let done = p.jobs.filter { $0.status == "success" }.count
        let progress = p.jobs.isEmpty ? "" : " · \(done)/\(p.jobs.count) jobs passed"
        let detail = NSMutableAttributedString(string: "\(p.project) #\(p.id)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.white,
        ])
        detail.append(NSAttributedString(string: " · \(p.ref)\(progress)", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))

        // The column takes whatever width is left after the icon, so the link can reach the right edge.
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        column.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleLabel = label(title, size: 15, bold: true, color: color)
        let link = linkButton("Open in Browser", open)
        let detailLabel = singleLine(attributed: detail)
        let timeLabel = singleLine(attributed: NSAttributedString(
            string: RelativeDateTimeFormatter().localizedString(for: p.updated ?? Date(), relativeTo: Date()),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        for v in [titleLabel, link, detailLabel, timeLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(v)
        }
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        link.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: column.topAnchor),
            link.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            link.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: link.leadingAnchor, constant: -8),
            detailLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 2),
            timeLabel.bottomAnchor.constraint(equalTo: column.bottomAnchor),
        ])

        let row = NSStackView(views: [icon, column])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.spacing = 12
        return row
    }

    /// A one-line label that truncates instead of wrapping, so it never changes the column width.
    private static func singleLine(attributed text: NSAttributedString) -> NSTextField {
        let t = NSTextField(labelWithAttributedString: text)
        t.lineBreakMode = .byTruncatingTail
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return t
    }

    /// One column per stage, colored by the worst job in it.
    private static func timeline(_ p: Pipeline) -> NSView {
        let stages = orderedStages(p.jobs)
        guard !stages.isEmpty else {
            return label("Stages appear when jobs load", size: 11, color: .secondaryLabelColor)
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 12
        for stage in stages {
            let jobs = p.jobs.filter { $0.stage == stage }
            let (name, color) = stageStatus(jobs.map(\.status))
            let icon = symbol(name, size: 20, color: color)
            let item = NSStackView(views: [icon, label(stage, size: 10, color: color)])
            item.orientation = .vertical
            item.alignment = .centerX
            item.spacing = 4
            row.addArrangedSubview(item)
        }
        // Trailing spacer: the stages stay together on the left instead of spreading across the card.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private static func jobRow(_ job: Job) -> NSView {
        let (name, color, text) = jobStyle(job.status)
        let icon = symbol(name, size: 13, color: color)
        let title = label(job.name, size: 12)
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(icon)
        row.addArrangedSubview(title)
        if job.status == "running" {
            // GitLab does not report progress for a job, so show an indeterminate bar.
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = true
            bar.controlSize = .small
            bar.startAnimation(nil)
            bar.widthAnchor.constraint(equalToConstant: 60).isActive = true
            row.addArrangedSubview(bar)
        }
        row.addArrangedSubview(label(text, size: 10, color: .secondaryLabelColor))
        return row
    }

    // MARK: - Status styling (green passed, orange running, grey pending, red failed)

    private static func overallStyle(_ p: Pipeline) -> (String, NSColor, String) {
        switch p.status {
        case "success", "passed": return ("checkmark.circle.fill", .systemGreen, "Pipeline passed")
        case "running": return ("circle.lefthalf.filled", .systemOrange, "Pipeline running")
        case "failed": return ("xmark.circle.fill", .systemRed, "Pipeline failed")
        case "canceled", "cancelled": return ("slash.circle", .tertiaryLabelColor, "Pipeline canceled")
        default: return ("circle", .tertiaryLabelColor, "Pipeline \(p.status)")
        }
    }

    private static func jobStyle(_ status: String) -> (String, NSColor, String) {
        switch status {
        case "success", "passed": return ("checkmark.circle.fill", .systemGreen, "passed")
        case "running": return ("circle.lefthalf.filled", .systemOrange, "running")
        case "failed": return ("xmark.circle.fill", .systemRed, "failed")
        case "manual": return ("pause.circle", .systemOrange, "manual")
        case "canceled", "cancelled": return ("slash.circle", .tertiaryLabelColor, "canceled")
        case "skipped": return ("minus.circle", .tertiaryLabelColor, "skipped")
        default: return ("circle", .tertiaryLabelColor, "waiting")
        }
    }

    /// A stage is failed if any job failed, running if any is running, passed if all passed, else pending.
    private static func stageStatus(_ statuses: [String]) -> (String, NSColor) {
        if statuses.contains("failed") { return ("xmark.circle.fill", .systemRed) }
        if statuses.contains("running") { return ("circle.lefthalf.filled", .systemOrange) }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == "success" || $0 == "passed" }) {
            return ("checkmark.circle.fill", .systemGreen)
        }
        return ("circle", .tertiaryLabelColor)
    }

    private static func orderedStages(_ jobs: [Job]) -> [String] {
        var seen: [String] = []
        for j in jobs where !seen.contains(j.stage) { seen.append(j.stage) }
        return seen
    }

    // MARK: - Small helpers

    private static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        view.contentTintColor = color
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    private static func label(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        // Wrapping labels with a set width, so long text wraps instead of pushing the row sideways.
        let t = NSTextField(wrappingLabelWithString: text)
        t.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        t.textColor = color
        t.preferredMaxLayoutWidth = width - 100
        t.alignment = .left   // stretched labels must not right-align their text
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return t
    }

    /// The counts line: one unwrapped line of plain text, so its words are never spread apart.
    private static func countsLabel(_ text: String) -> NSTextField {
        let t = NSTextField(labelWithString: text)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        t.lineBreakMode = .byClipping
        t.usesSingleLineMode = true
        t.alignment = .left
        return t
    }

    /// Keeps a view at the left of a full-width stack: a horizontal row whose spacer takes the rest.
    private static func leftAligned(_ view: NSView) -> NSView {
        view.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [view, spacer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        return row
    }

    /// A 1-point line. An NSBox separator takes more height than it draws, which left a gap.
    private static func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true   // width comes from the stack
        return line
    }

    private static func linkButton(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = CardButton(title: title, action: action)
        b.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.bezelStyle = .accessoryBarAction
        b.font = .systemFont(ofSize: 11)
        return b
    }
}

/// NSButton that runs a closure, so the card can call back into the menu controller.
final class CardButton: NSButton {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func run() { handler() }
}
