import ClassicToolbox

/// The game is always shown at an integer magnification of its 1987 pixels.
public enum WindowScale {
    /// Magnifications offered in the View menu.
    public static let range = 1...4

    /// The largest magnification at which `window` fits in `width` × `height`
    /// pixels, at least 1 and (if `limit` is set) at most that.
    public static func fitting(_ window: Rect, width: Int, height: Int, limit: Int? = range.upperBound) -> Int {
        let s = min(width / max(1, window.width), height / max(1, window.height))
        return max(1, limit.map { min($0, s) } ?? s)
    }

    /// Default for a first launch: the largest the screen's usable area allows, up
    /// to 4×, and 2× if the screen size is unknown.
    public static func initial(_ window: Rect, screenWidth: Int?, screenHeight: Int?) -> Int {
        guard let screenWidth, let screenHeight else { return 2 }
        return fitting(window, width: screenWidth, height: screenHeight)
    }
}

/// Keys the platforms store preferences under (UserDefaults on macOS, a file on
/// Windows), so a setting means the same thing everywhere.
public enum PreferenceKey {
    /// Persistent high score (the original reset it each launch).
    public static let hiScore = "HiScore"
    /// Integer magnification of the game window.
    public static let scale = "Scale"
    /// Override for FramePacer.defaultLoopsPerSecond, for calibration.
    public static let loopsPerSecond = "LoopsPerSecond"
}
