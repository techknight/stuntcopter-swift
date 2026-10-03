import ClassicToolbox

/// The pointer the game reads while the real cursor is hidden for play: driven by
/// raw mouse deltas and confined to the 512×342 Mac Plus screen, so the copter
/// can't be dragged past the edges the 1987 version had.
public struct VirtualPointer: Sendable {
    /// The Mac Plus screen, in global coordinates.
    public static let screen = Rect(top: 0, left: 0, bottom: 342, right: 512)

    public private(set) var x: Double
    public private(set) var y: Double

    /// Starts at `p`, in game-window coordinates.
    public init(at p: Point) {
        x = Double(p.h)
        y = Double(p.v)
    }

    /// GetMouse's answer, in game-window coordinates.
    public var point: Point { Point(h: Int(x.rounded(.down)), v: Int(y.rounded(.down))) }

    /// Applies a mouse delta measured in screen pixels while the game is drawn at an
    /// integer magnification `scale`; `windowOrigin` is the game window's global
    /// position (StuntCopterGame.windowGlobalOrigin) so the clamp is to the screen.
    public mutating func move(dx: Double, dy: Double, scale: Int, windowOrigin: Point) {
        let s = Double(max(1, scale))
        let screen = VirtualPointer.screen
        x = min(max(x + dx / s, Double(screen.left - windowOrigin.h)), Double(screen.right - windowOrigin.h))
        y = min(max(y + dy / s, Double(screen.top - windowOrigin.v)), Double(screen.bottom - windowOrigin.v))
    }
}
