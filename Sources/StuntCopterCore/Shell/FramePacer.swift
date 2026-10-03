/// Turns wall-clock time into game loop iterations. The 1987 loop ran as fast as
/// the CPU allowed; here every platform's frame callback asks how many loops to
/// run since the last frame, at `loopsPerSecond` × the game's current rate factor.
public struct FramePacer: Sendable {
    /// In-game loops per second at NORMAL speed with sound on: the original on a
    /// Mac Plus, measured in an emulator (see StuntCopterGame.loopRateFactor).
    public static let defaultLoopsPerSecond = 30.0
    /// A frame longer than this (the app was stalled) doesn't try to catch up.
    public static let maxFrameInterval = 0.25
    /// Loops per frame cap; beyond it the backlog is dropped instead.
    public static let maxStepsPerFrame = 8

    public var loopsPerSecond: Double
    private var lastTime = 0.0
    private var accumulator = 0.0

    public init(loopsPerSecond: Double = FramePacer.defaultLoopsPerSecond) {
        self.loopsPerSecond = loopsPerSecond > 0 ? loopsPerSecond : FramePacer.defaultLoopsPerSecond
    }

    /// Forget the previous frame time, e.g. after a modal dialog, so the first frame
    /// afterwards runs no loops rather than a backlog.
    public mutating func reset() {
        lastTime = 0
        accumulator = 0
    }

    /// How many game loops to run for the frame at `now` (seconds, any monotonic
    /// origin), given the game's rate factor for that frame.
    public mutating func steps(at now: Double, rateFactor: Double) -> Int {
        defer { lastTime = now }
        guard lastTime > 0 else { return 0 }
        accumulator += min(now - lastTime, FramePacer.maxFrameInterval) * loopsPerSecond * rateFactor
        var steps = 0
        while accumulator >= 1 && steps < FramePacer.maxStepsPerFrame {
            accumulator -= 1
            steps += 1
        }
        if steps == FramePacer.maxStepsPerFrame { accumulator = 0 }
        return steps
    }
}
