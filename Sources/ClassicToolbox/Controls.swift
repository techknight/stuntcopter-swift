/// A standard control (Inside Macintosh I-309): push button, check box or radio
/// button, drawn with QuickDraw into its owner window's bitmap.
public final class Control {
    public enum Kind: Sendable { case pushButton, checkBox, radioButton }

    public let kind: Kind
    public var contrlRect: Rect
    public var contrlTitle: String
    public var contrlValue: Int
    public var contrlVis: Bool
    /// 0 = normal, 1…253 = part highlighted, 255 = inactive (I-322).
    public var contrlHilite = 0
    /// The window the control lives in.
    public let owner: GrafPort
    /// The owner's real bitmap (drawing must not go to a SetPortBits'd offscreen).
    public let ownerBits: BitMap

    public init(kind: Kind, rect: Rect, title: String, value: Int = 0, visible: Bool, owner: GrafPort) {
        self.kind = kind
        contrlRect = rect
        contrlTitle = title
        contrlValue = value
        contrlVis = visible
        self.owner = owner
        ownerBits = owner.portBits
    }

    public convenience init(template t: ControlTemplate, owner: GrafPort) {
        let kind: Kind = switch t.procID & 0xF {
        case 1: .checkBox
        case 2: .radioButton
        default: .pushButton
        }
        self.init(kind: kind, rect: t.boundsRect, title: t.title, value: t.value, visible: t.visible, owner: owner)
    }
}

extension QuickDraw {
    /// Runs `body` with thePort set to the control's window and its real bitmap.
    func withOwnerPort(_ c: Control, _ body: () -> Void) {
        let savedPort = thePort
        SetPort(c.owner)
        let savedBits = thePort.portBits
        SetPortBits(c.ownerBits)
        let savedFace = thePort.txFace
        TextFace([])
        body()
        TextFace(savedFace)
        SetPortBits(savedBits)
        SetPort(savedPort)
    }

    /// Draws one control (the standard CDEF 0 look).
    public func Draw1Control(_ c: Control) {
        guard c.contrlVis else { return }
        withOwnerPort(c) {
            let r = c.contrlRect
            switch c.kind {
            case .pushButton:
                // System 6's CDEF 0 rounds push buttons with an oval of half the button's height.
                let oval = r.height / 2
                EraseRoundRect(r, oval, oval)
                FrameRoundRect(r, oval, oval)
                let w = StringWidth(c.contrlTitle)
                let baseline = r.top + (r.height - (textAscent + textDescent)) / 2 + textAscent
                MoveTo(r.left + (r.width - w) / 2, baseline)
                DrawString(c.contrlTitle)
                if c.contrlHilite > 0 && c.contrlHilite < 254 {
                    InvertRoundRect(r, oval, oval)
                }
            case .radioButton, .checkBox:
                EraseRect(r)
                let box = Rect(top: r.top + (r.height - 12) / 2, left: r.left + 2,
                               bottom: r.top + (r.height - 12) / 2 + 12, right: r.left + 14)
                if c.kind == .radioButton {
                    FrameOval(box)
                    if c.contrlValue != 0 { PaintOval(box.insetBy(3, 3)) }
                } else {
                    FrameRect(box)
                    if c.contrlValue != 0 {
                        MoveTo(box.left, box.top); LineTo(box.right - 1, box.bottom - 1)
                        MoveTo(box.right - 1, box.top); LineTo(box.left, box.bottom - 1)
                    }
                }
                if c.contrlHilite > 0 && c.contrlHilite < 254 {
                    FrameRect(box.insetBy(1, 1))
                }
                let baseline = r.top + (r.height - (textAscent + textDescent)) / 2 + textAscent
                MoveTo(box.right + 4, baseline)
                DrawString(c.contrlTitle)
            }
        }
    }

    public func ShowControl(_ c: Control) {
        guard !c.contrlVis else { return }
        c.contrlVis = true
        Draw1Control(c)
    }

    /// HideControl erases the control and adds its rect to the window's update region.
    public func HideControl(_ c: Control) {
        guard c.contrlVis else { return }
        c.contrlVis = false
        withOwnerPort(c) {
            EraseRect(c.contrlRect)
            InvalRect(c.contrlRect)
        }
    }

    public func SetCTitle(_ c: Control, _ title: String) {
        c.contrlTitle = title
        Draw1Control(c)
    }

    public func SetCtlValue(_ c: Control, _ value: Int) {
        c.contrlValue = value
        Draw1Control(c)
    }

    public func HiliteControl(_ c: Control, _ state: Int) {
        guard c.contrlHilite != state else { return }
        c.contrlHilite = state
        Draw1Control(c)
    }

    public func SizeControl(_ c: Control, _ w: Int, _ h: Int) {
        c.contrlRect.right = c.contrlRect.left + w
        c.contrlRect.bottom = c.contrlRect.top + h
        Draw1Control(c)
    }

    public func MoveControl(_ c: Control, _ h: Int, _ v: Int) {
        OffsetRect(&c.contrlRect, h - c.contrlRect.left, v - c.contrlRect.top)
        Draw1Control(c)
    }

    /// Adds a rect to the current window's update region.
    public func InvalRect(_ r: Rect) {
        let rgn = thePort.updateRgn
        UnionRgn(rgn, Region(rect: r.intersection(thePort.portRect)), rgn)
    }
}
