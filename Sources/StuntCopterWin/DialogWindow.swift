import CStuntCopterWin
import ClassicToolbox
import StuntCopterCore
import WinSDK

/// A borderless popup showing a ClassicDialog inside its dBoxProc frame, and the
/// ModalDialog event handling for it.
@MainActor
final class DialogWindow {
    static let className = "StuntCopterDialog"

    let framed: DialogFrame
    let window: Win32Window
    private let game: StuntCopterGame
    private let owner: Win32Window
    /// The item ModalDialog should return, once one is hit.
    private var result: Int?
    var dialog: ClassicDialog { framed.dialog }

    init(dialog: ClassicDialog, game: StuntCopterGame, owner: Win32Window) {
        framed = DialogFrame(dialog: dialog)
        self.game = game
        self.owner = owner
        window = Win32Window(className: DialogWindow.className, title: "", style: wsPopup, owner: owner.hwnd,
                             bitmap: framed.composite)
        window.onMouseDown = { [weak self] p in
            guard let self else { return }
            if let item = game.dialogMouseDown(dialog, self.framed.contentPoint(p)) {
                self.refresh()
                self.result = item
            }
            self.refresh()
        }
        window.onMouseDragged = { [weak self] p in
            guard let self else { return }
            game.dialogMouseDragged(dialog, self.framed.contentPoint(p))
            self.refresh()
        }
        window.onMouseUp = { [weak self] p in
            guard let self else { return }
            let item = game.dialogMouseUp(dialog, self.framed.contentPoint(p))
            self.refresh()
            if let item { self.result = item }
        }
        window.onKey = { [weak self] key in
            guard let self, let item = game.dialogKey(dialog, key.character) else { return false }
            // ModalDialog flashes the button it's returning.
            if let c = game.GetDItemControl(dialog, item) {
                game.HiliteControl(c, 1)
                self.refresh()
                Sleep(DWORD(8 * 1000 / 60))
                game.HiliteControl(c, 0)
                self.refresh()
            }
            self.result = item
            return true
        }
        window.onMessage = { msg, _, _ in
            // The dialog goes away with the game window; never on its own.
            msg == WM_CLOSE ? 0 : nil
        }
    }

    /// Copies the dialog's port into the framed composite and redisplays it.
    func refresh() {
        framed.refresh()
        window.refresh()
    }

    /// Places the window where the 1987 dialog appeared relative to the game window,
    /// at the game window's magnification, kept on the monitor.
    func position(windowOrigin: Point) {
        let s = owner.scale
        window.scale = s
        let local = framed.origin(relativeToWindowAt: windowOrigin)
        let r = owner.imageRect
        var topLeft = POINT(x: Int32(r.x + local.h * s), y: Int32(r.y + local.v * s))
        _ = ClientToScreen(owner.hwnd, &topLeft)
        let w = Int32(framed.composite.width * s), h = Int32(framed.composite.height * s)
        var x = topLeft.x, y = topLeft.y
        var mi = MONITORINFO()
        mi.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if let monitor = MonitorFromWindow(owner.hwnd, DWORD(MONITOR_DEFAULTTONEAREST)), GetMonitorInfoW(monitor, &mi).boolValue {
            let work = mi.rcWork
            x = min(max(x, work.left), work.right - w)
            y = min(max(y, work.top), work.bottom - h)
        }
        _ = SetWindowPos(window.hwnd, nil, x, y, w, h, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
    }

    func show() {
        _ = ShowWindow(window.hwnd, SW_SHOW)
        _ = SetForegroundWindow(window.hwnd)
        _ = SetFocus(window.hwnd)
    }

    func hide() {
        _ = ShowWindow(window.hwnd, SW_HIDE)
    }

    /// Runs a nested message loop with the game window disabled until an item is hit.
    func runModal() -> Int {
        result = nil
        _ = EnableWindow(owner.hwnd, false)
        var msg = MSG()
        while result == nil {
            guard GetMessageW(&msg, nil, 0, 0).boolValue else {   // WM_QUIT
                PostQuitMessage(0)
                result = 1
                break
            }
            _ = TranslateMessage(&msg)
            _ = DispatchMessageW(&msg)
        }
        _ = EnableWindow(owner.hwnd, true)
        return result ?? 1
    }
}
