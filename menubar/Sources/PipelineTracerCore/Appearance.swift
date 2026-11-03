import AppKit

/// GitLab behavior preferences saved in UserDefaults.
enum PipelineTracerPrefs {
    private static let gitlabRefreshKey = "pipelinetracer.gitlabRefreshSeconds"
    private static let pipelineHoursKey = "pipelinetracer.pipelineHours"
    private static let mergeButtonKey = "pipelinetracer.mergeButton"
    private static let rememberPlaceKey = "pipelinetracer.rememberPlace"

    static let gitlabRefreshChoices = [10, 20, 30, 40, 50, 60]
    static let pipelineHourChoices = [1, 2, 4, 6, 8, 12, 24]

    /// Seconds between GitLab refreshes.
    static var gitlabRefreshSeconds: Int {
        get { int(gitlabRefreshKey, 60, gitlabRefreshChoices) }
        set { UserDefaults.standard.set(newValue, forKey: gitlabRefreshKey) }
    }
    /// How far back finished pipelines are listed, in hours.
    static var pipelineHours: Int {
        get { int(pipelineHoursKey, 2, pipelineHourChoices) }
        set { UserDefaults.standard.set(newValue, forKey: pipelineHoursKey) }
    }
    /// Shows Merge on ready merge requests (asks to confirm). On by default; turn off under Options › GitLab.
    static var mergeButton: Bool {
        get { bool(mergeButtonKey, true) }
        set { UserDefaults.standard.set(newValue, forKey: mergeButtonKey) }
    }
    /// Off returns the panel to the overview each time it opens.
    static var rememberPlace: Bool {
        get { bool(rememberPlaceKey, false) }
        set { UserDefaults.standard.set(newValue, forKey: rememberPlaceKey) }
    }

    private static func int(_ key: String, _ fallback: Int, _ allowed: [Int]) -> Int {
        let v = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return allowed.contains(v) ? v : fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}

/// What a piece of text means, so colors stay consistent across the bar and the menus.
enum Tone {
    case good, caution, warning, bad, running, dim, plain
}

enum Palette {
    /// Dropdown text color. Plain text uses the normal label color.
    static func menuColor(_ tone: Tone) -> NSColor? {
        switch tone {
        case .good: return .systemGreen
        case .caution: return .systemYellow
        case .warning: return .systemOrange
        case .bad: return .systemRed
        case .running: return .systemBlue
        case .dim: return .secondaryLabelColor
        case .plain: return nil
        }
    }

    static func attributed(_ text: String, _ tone: Tone, font: NSFont = .menuFont(ofSize: 0)) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if let c = menuColor(tone) { attrs[.foregroundColor] = c }
        return NSAttributedString(string: text, attributes: attrs)
    }
}
