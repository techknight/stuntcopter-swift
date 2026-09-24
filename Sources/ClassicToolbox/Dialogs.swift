/// A modal dialog built from 'DLOG'/'DITL' resources (Inside Macintosh I-397),
/// drawn into its own 1-bit port. The host window system shows `port.portBits`
/// and forwards mouse/keyboard events to the `dialog…` calls below.
public final class ClassicDialog {
    public let id: Int
    public let template: DialogTemplate
    public let items: [DialogItemTemplate]
    public let port: GrafPort
    /// Controls for button/check box/radio items, keyed by 1-based item number.
    public private(set) var controls: [Int: Control] = [:]
    var icons: [Int: BitMap] = [:]
    public var visible = false
    var tracking: Int?

    public init(id: Int, resources: ResourceFork) throws {
        self.id = id
        template = try resources.dialog(id)
        items = try resources.itemList(template.itemsID)
        let b = template.boundsRect
        port = GrafPort(size: Rect(top: 0, left: 0, bottom: b.height, right: b.width))
        for (i, item) in items.enumerated() {
            let n = i + 1
            switch item.kind {
            case .button:
                controls[n] = Control(kind: .pushButton, rect: item.rect, title: item.text, visible: true, owner: port)
            case .radioButton:
                controls[n] = Control(kind: .radioButton, rect: item.rect, title: item.text, visible: true, owner: port)
            case .checkBox:
                controls[n] = Control(kind: .checkBox, rect: item.rect, title: item.text, visible: true, owner: port)
            case .icon:
                icons[n] = try? resources.icon(item.resourceID)
            default:
                break
            }
        }
    }

    /// Size of the content area (the DLOG boundsRect).
    public var size: Rect { port.portRect }

    public func item(at pt: Point) -> Int? {
        for (i, item) in items.enumerated() where !item.disabled && item.rect.contains(pt) {
            return i + 1
        }
        return nil
    }
}

extension QuickDraw {
    /// GetDItem for control items.
    public func GetDItemControl(_ d: ClassicDialog, _ item: Int) -> Control? { d.controls[item] }

    public func GetDItemRect(_ d: ClassicDialog, _ item: Int) -> Rect { d.items[item - 1].rect }

    /// ShowWindow for a dialog: the Window Manager erases the content, and the
    /// first update draws the items.
    public func ShowDialog(_ d: ClassicDialog) {
        d.visible = true
        DrawDialog(d)
    }

    public func HideDialog(_ d: ClassicDialog) {
        d.visible = false
        d.tracking = nil
    }

    public func DrawDialog(_ d: ClassicDialog) {
        let saved = thePort
        SetPort(d.port)
        let savedFace = thePort.txFace
        TextFace([])
        EraseRect(d.port.portRect)
        for (i, item) in d.items.enumerated() {
            let n = i + 1
            if let c = d.controls[n] {
                Draw1Control(c)
            } else if item.kind == .staticText {
                TextBox(item.text, item.rect)
            } else if let icon = d.icons[n] {
                CopyBits(icon, d.port.portBits, icon.bounds, item.rect, srcCopy, nil)
            }
        }
        TextFace(savedFace)
        SetPort(saved)
    }

    // MARK: ModalDialog event handling

    /// Mouse down in dialog-local coordinates. Returns an item number immediately
    /// for non-control items; controls start tracking and report on mouse up.
    public func dialogMouseDown(_ d: ClassicDialog, _ pt: Point) -> Int? {
        guard let n = d.item(at: pt) else { return nil }
        if let c = d.controls[n] {
            d.tracking = n
            HiliteControl(c, 1)
            return nil
        }
        return n
    }

    public func dialogMouseDragged(_ d: ClassicDialog, _ pt: Point) {
        guard let n = d.tracking, let c = d.controls[n] else { return }
        HiliteControl(c, c.contrlRect.contains(pt) ? 1 : 0)
    }

    public func dialogMouseUp(_ d: ClassicDialog, _ pt: Point) -> Int? {
        guard let n = d.tracking, let c = d.controls[n] else { return nil }
        d.tracking = nil
        HiliteControl(c, 0)
        return c.contrlRect.contains(pt) ? n : nil
    }

    /// Return or Enter selects item 1, as ModalDialog does.
    public func dialogKey(_ d: ClassicDialog, _ char: Character) -> Int? {
        (char == "\r" || char == "\u{3}") ? 1 : nil
    }
}
