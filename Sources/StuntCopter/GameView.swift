import AppKit
import ClassicToolbox

/// Shows a 1-bit bitmap at the largest integer scale that fits, centered on black
/// (letterboxed in full screen), and reports input in bitmap coordinates.
final class PixelView: NSView {
    var bitmap: BitMap {
        didSet { lastGeneration = -1; refresh() }
    }
    private let imageLayer = CALayer()
    private var lastGeneration = -1

    var onMouseDown: ((Point, NSEvent) -> Void)?
    var onMouseDragged: ((Point, NSEvent) -> Void)?
    var onMouseUp: ((Point, NSEvent) -> Void)?
    var onMouseMoved: ((NSEvent) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    init(bitmap: BitMap) {
        self.bitmap = bitmap
        super.init(frame: NSRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.contentsGravity = .resize
        imageLayer.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Integer magnification of the bitmap in points.
    var scale: Int {
        max(1, min(Int(bounds.width) / max(1, bitmap.width), Int(bounds.height) / max(1, bitmap.height)))
    }

    /// Where the bitmap is drawn, in view coordinates.
    var imageRect: CGRect {
        let s = CGFloat(scale)
        let w = CGFloat(bitmap.width) * s, h = CGFloat(bitmap.height) * s
        return CGRect(x: ((bounds.width - w) / 2).rounded(.down), y: ((bounds.height - h) / 2).rounded(.down),
                      width: w, height: h)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = imageRect
        CATransaction.commit()
    }

    /// Pushes the bitmap to the screen if it changed.
    func refresh() {
        guard bitmap.generation != lastGeneration else { return }
        lastGeneration = bitmap.generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = makeCGImage(bitmap)
        CATransaction.commit()
    }

    /// A view point converted to bitmap coordinates.
    func bitmapPoint(_ viewPoint: NSPoint) -> Point {
        let r = imageRect, s = CGFloat(scale)
        return Point(h: Int(((viewPoint.x - r.minX) / s).rounded(.down)),
                     v: Int(((viewPoint.y - r.minY) / s).rounded(.down)))
    }

    func bitmapPoint(_ event: NSEvent) -> Point {
        bitmapPoint(convert(event.locationInWindow, from: nil))
    }

    /// A bitmap point in screen coordinates (for warping the cursor).
    func screenPoint(_ p: Point) -> NSPoint? {
        guard let window else { return nil }
        let r = imageRect, s = CGFloat(scale)
        let v = NSPoint(x: r.minX + (CGFloat(p.h) + 0.5) * s, y: r.minY + (CGFloat(p.v) + 0.5) * s)
        return window.convertPoint(toScreen: convert(v, to: nil))
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(bitmapPoint(event), event) }
    override func mouseDragged(with event: NSEvent) {
        onMouseMoved?(event)
        onMouseDragged?(bitmapPoint(event), event)
    }
    override func mouseUp(with event: NSEvent) { onMouseUp?(bitmapPoint(event), event) }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?(event) }
    override func rightMouseDown(with event: NSEvent) { onMouseDown?(bitmapPoint(event), event) }
    override func rightMouseUp(with event: NSEvent) { onMouseUp?(bitmapPoint(event), event) }
    override func otherMouseDown(with event: NSEvent) { onMouseDown?(bitmapPoint(event), event) }
    override func otherMouseUp(with event: NSEvent) { onMouseUp?(bitmapPoint(event), event) }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}
