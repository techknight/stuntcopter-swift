import ClassicToolbox

/// What the game needs from the platform (the AppKit shell, or a fake in tests).
/// Each call corresponds to a Toolbox call the Pascal made outside QuickDraw.
@MainActor
public protocol GameHost: AnyObject {
    /// GetMouse: the pointer in the game window's local coordinates. While the
    /// cursor is hidden for play this is a virtual pointer driven by mouse deltas.
    func getMouse() -> Point
    /// HideCursor / ShowCursor: the host captures or releases the mouse for play.
    func hideCursor()
    func showCursor()
    /// DrawMenuBar after InsertMenu/DeleteMenu of the "(Backspace to Exit)" menu and
    /// Enable/DisableItem of the other menus.
    func drawMenuBar(messageMenuShown: Bool, menusEnabled: Bool)
    /// CheckItem for Options ▸ Sound.
    func checkSoundItem(_ on: Bool)
    /// ShowWindow / HideWindow for a dialog.
    func showDialogWindow(_ d: ClassicDialog)
    func hideDialogWindow(_ d: ClassicDialog)
    /// ModalDialog: blocks (running a nested event loop) until an item is hit.
    func modalDialog(_ d: ClassicDialog) -> Int
    /// A busy-wait on TickCount inside a modal dialog; keep the screen live.
    func pause(ticks: Int)
    /// Persistent high score (a modern addition; the original reset it each launch).
    func savedHiScore() -> Int
    func hiScoreChanged(_ hiScore: Int)
    /// File ▸ Quit.
    func quit()
}

/// Input events queued by the host, drained by `tick()` like GetNextEvent.
public enum GameEvent: Sendable {
    case mouseDown(Point)
    case mouseDragged(Point)
    case mouseUp(Point)
    case keyDown(Character)
}
