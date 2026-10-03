import AppKit
import ClassicToolbox
import StuntCopterCore

/// A borderless panel that shows a ClassicDialog with a dBoxProc-style frame and
/// runs ModalDialog's event handling.
@MainActor
final class DialogPanel: NSPanel {
    let framed: DialogFrame
    let game: StuntCopterGame
    let pixelView: PixelView
    var dialog: ClassicDialog { framed.dialog }

    init(dialog: ClassicDialog, game: StuntCopterGame) {
        framed = DialogFrame(dialog: dialog)
        self.game = game
        pixelView = PixelView(bitmap: framed.composite)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        contentView = pixelView
        isOpaque = true
        hasShadow = true
        level = .modalPanel

        pixelView.onMouseDown = { [weak self] p, _ in
            guard let self else { return }
            if let item = game.dialogMouseDown(dialog, self.framed.contentPoint(p)) {
                self.refresh()
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: item))
            }
            self.refresh()
        }
        pixelView.onMouseDragged = { [weak self] p, _ in
            guard let self else { return }
            game.dialogMouseDragged(dialog, self.framed.contentPoint(p))
            self.refresh()
        }
        pixelView.onMouseUp = { [weak self] p, _ in
            guard let self else { return }
            let item = game.dialogMouseUp(dialog, self.framed.contentPoint(p))
            self.refresh()
            if let item { NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: item)) }
        }
        pixelView.onKeyDown = { [weak self] event in
            guard let self else { return false }
            guard let key = event.hostKey else { return false }
            if let item = game.dialogKey(dialog, key.character) {
                // ModalDialog flashes the button it's returning.
                if let c = game.GetDItemControl(dialog, item) {
                    game.HiliteControl(c, 1); self.refresh(); CATransaction.flush()
                    Thread.sleep(forTimeInterval: 8.0 / 60)
                    game.HiliteControl(c, 0); self.refresh()
                }
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: item))
                return true
            }
            return false
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Copies the dialog's port into the framed composite and redisplays it.
    func refresh() {
        framed.refresh()
        pixelView.refresh()
    }

    /// Places the panel where the 1987 dialog appeared relative to the game window,
    /// at the game window's current magnification.
    func position(over gameView: PixelView, windowOrigin: Point) {
        let s = CGFloat(gameView.scale)
        let local = framed.origin(relativeToWindowAt: windowOrigin)
        let size = NSSize(width: CGFloat(framed.composite.width) * s, height: CGFloat(framed.composite.height) * s)
        guard let window = gameView.window else { return }
        let r = gameView.imageRect
        let topLeftInView = NSPoint(x: r.minX + CGFloat(local.h) * s, y: r.minY + CGFloat(local.v) * s)
        let topLeftOnScreen = window.convertPoint(toScreen: gameView.convert(topLeftInView, to: nil))
        var frame = NSRect(x: topLeftOnScreen.x, y: topLeftOnScreen.y - size.height, width: size.width, height: size.height)
        if let screen = window.screen?.visibleFrame {   // keep it on screen
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        setFrame(frame, display: false)
    }
}
