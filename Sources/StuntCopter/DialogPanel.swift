import AppKit
import ClassicToolbox
import StuntCopterCore

/// A borderless panel that shows a ClassicDialog with a dBoxProc-style frame and
/// runs ModalDialog's event handling.
@MainActor
final class DialogPanel: NSPanel {
    /// dBoxProc frame drawn outside the content: 1 black, 1 white, 2 black.
    static let frameWidth = 4

    let dialog: ClassicDialog
    let game: StuntCopterGame
    let pixelView: PixelView
    private let composite: BitMap

    init(dialog: ClassicDialog, game: StuntCopterGame) {
        self.dialog = dialog
        self.game = game
        let f = DialogPanel.frameWidth
        let c = dialog.size
        composite = BitMap(bounds: Rect(top: 0, left: 0, bottom: c.height + 2 * f, right: c.width + 2 * f))
        pixelView = PixelView(bitmap: composite)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        contentView = pixelView
        isOpaque = true
        hasShadow = true
        level = .modalPanel
        drawFrame()

        pixelView.onMouseDown = { [weak self] p, _ in
            guard let self else { return }
            if let item = game.dialogMouseDown(dialog, self.contentPoint(p)) {
                self.refresh()
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: item))
            }
            self.refresh()
        }
        pixelView.onMouseDragged = { [weak self] p, _ in
            guard let self else { return }
            game.dialogMouseDragged(dialog, self.contentPoint(p))
            self.refresh()
        }
        pixelView.onMouseUp = { [weak self] p, _ in
            guard let self else { return }
            let item = game.dialogMouseUp(dialog, self.contentPoint(p))
            self.refresh()
            if let item { NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: item)) }
        }
        pixelView.onKeyDown = { [weak self] event in
            guard let self else { return false }
            if event.modifierFlags.contains(.command) { return false }
            let ch: Character = switch event.keyCode {
            case 76: "\u{3}"    // keypad Enter
            case 53: "\u{1B}"   // Esc
            default: event.characters?.first ?? " "
            }
            if let item = game.dialogKey(dialog, ch) {
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

    private func contentPoint(_ p: Point) -> Point {
        Point(h: p.h - DialogPanel.frameWidth, v: p.v - DialogPanel.frameWidth)
    }

    private func drawFrame() {
        let w = composite.width, h = composite.height
        for y in 0..<h {
            for x in 0..<w {
                let d = min(x, y, w - 1 - x, h - 1 - y)   // distance from the outer edge
                if d < DialogPanel.frameWidth { composite.pixels[y * w + x] = (d == 1) ? 0 : 1 }
            }
        }
    }

    /// Copies the dialog's port into the framed composite and redisplays it.
    func refresh() {
        let src = dialog.port.portBits
        let f = DialogPanel.frameWidth
        for y in 0..<src.height {
            let s = y * src.width, d = (y + f) * composite.width + f
            composite.pixels.replaceSubrange(d..<(d + src.width), with: src.pixels[s..<(s + src.width)])
        }
        composite.markChanged()
        pixelView.refresh()
    }

    /// Places the panel where the 1987 dialog appeared relative to the game window,
    /// at the game window's current magnification.
    func position(over gameView: PixelView, windowOrigin: Point) {
        let s = CGFloat(gameView.scale)
        let f = CGFloat(DialogPanel.frameWidth)
        let b = dialog.template.boundsRect
        let local = Point(h: b.left - windowOrigin.h - DialogPanel.frameWidth, v: b.top - windowOrigin.v - DialogPanel.frameWidth)
        let size = NSSize(width: (CGFloat(dialog.size.width) + 2 * f) * s, height: (CGFloat(dialog.size.height) + 2 * f) * s)
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
