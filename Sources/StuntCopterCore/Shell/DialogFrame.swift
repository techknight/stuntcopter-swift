import ClassicToolbox

/// A ClassicDialog's content inside the dBoxProc window frame the original drew
/// around it, as one bitmap the platform can show in a borderless window.
@MainActor
public final class DialogFrame {
    /// The frame from the outside in, measured from the original on an emulated
    /// Mac Plus: 1 black, 2 white, 2 black, 3 white.
    public static let pattern: [UInt8] = [1, 0, 0, 1, 1, 0, 0, 0]
    public static let width = pattern.count

    public let dialog: ClassicDialog
    /// Frame plus content; refreshed from the dialog's port by `refresh()`.
    public let composite: BitMap

    public init(dialog: ClassicDialog) {
        self.dialog = dialog
        let f = DialogFrame.width
        let c = dialog.size
        composite = BitMap(bounds: Rect(top: 0, left: 0, bottom: c.height + 2 * f, right: c.width + 2 * f))
        let w = composite.width, h = composite.height
        for y in 0..<h {
            for x in 0..<w {
                let d = min(x, y, w - 1 - x, h - 1 - y)   // distance from the outer edge
                if d < f { composite.pixels[y * w + x] = DialogFrame.pattern[d] }
            }
        }
        composite.markChanged()
    }

    /// Copies the dialog's port into the framed composite.
    public func refresh() {
        let src = dialog.port.portBits
        let f = DialogFrame.width
        for y in 0..<src.height {
            let s = y * src.width, d = (y + f) * composite.width + f
            composite.pixels.replaceSubrange(d..<(d + src.width), with: src.pixels[s..<(s + src.width)])
        }
        composite.markChanged()
    }

    /// A point in the composite, in the dialog's own coordinates.
    public func contentPoint(_ p: Point) -> Point {
        Point(h: p.h - DialogFrame.width, v: p.v - DialogFrame.width)
    }

    /// Where the composite's top-left corner sat relative to the game window's content
    /// in 1987 (both windows were at fixed global positions; `windowOrigin` is
    /// StuntCopterGame.windowGlobalOrigin). Multiply by the magnification to place it.
    public func origin(relativeToWindowAt windowOrigin: Point) -> Point {
        let b = dialog.template.boundsRect
        return Point(h: b.left - windowOrigin.h - DialogFrame.width, v: b.top - windowOrigin.v - DialogFrame.width)
    }
}
