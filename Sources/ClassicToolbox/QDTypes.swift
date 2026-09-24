// QuickDraw geometry: Point and Rect with the original field order and semantics.
// Coordinates are grid lines between pixels; a Rect covers pixels
// left..<right and top..<bottom (Inside Macintosh I-138).

public struct Point: Equatable, Hashable, Sendable {
    public var v: Int
    public var h: Int

    public init(h: Int, v: Int) {
        self.h = h
        self.v = v
    }

    public static let zero = Point(h: 0, v: 0)
}

public struct Rect: Equatable, Hashable, Sendable {
    public var top: Int
    public var left: Int
    public var bottom: Int
    public var right: Int

    public init(top: Int, left: Int, bottom: Int, right: Int) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// SetRect(r, left, top, right, bottom) argument order.
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.init(top: top, left: left, bottom: bottom, right: right)
    }

    public static let zero = Rect(top: 0, left: 0, bottom: 0, right: 0)

    public var topLeft: Point {
        get { Point(h: left, v: top) }
        set { left = newValue.h; top = newValue.v }
    }

    public var botRight: Point {
        get { Point(h: right, v: bottom) }
        set { right = newValue.h; bottom = newValue.v }
    }

    public var width: Int { right - left }
    public var height: Int { bottom - top }
    public var isEmpty: Bool { right <= left || bottom <= top }

    public func offsetBy(_ dh: Int, _ dv: Int) -> Rect {
        Rect(top: top + dv, left: left + dh, bottom: bottom + dv, right: right + dh)
    }

    public func insetBy(_ dh: Int, _ dv: Int) -> Rect {
        var r = Rect(top: top + dv, left: left + dh, bottom: bottom - dv, right: right - dh)
        if r.isEmpty { r = .zero }
        return r
    }

    /// SectRect; returns .zero when the rects don't intersect.
    public func intersection(_ o: Rect) -> Rect {
        let r = Rect(top: max(top, o.top), left: max(left, o.left),
                     bottom: min(bottom, o.bottom), right: min(right, o.right))
        return r.isEmpty ? .zero : r
    }

    public func union(_ o: Rect) -> Rect {
        if isEmpty { return o }
        if o.isEmpty { return self }
        return Rect(top: min(top, o.top), left: min(left, o.left),
                    bottom: max(bottom, o.bottom), right: max(right, o.right))
    }

    public func contains(_ pt: Point) -> Bool {
        pt.h >= left && pt.h < right && pt.v >= top && pt.v < bottom
    }
}

// MARK: - Toolbox-style free functions (so ported Pascal reads the same)

public func SetRect(_ r: inout Rect, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
    r = Rect(left: left, top: top, right: right, bottom: bottom)
}

public func OffsetRect(_ r: inout Rect, _ dh: Int, _ dv: Int) {
    r = r.offsetBy(dh, dv)
}

public func InsetRect(_ r: inout Rect, _ dh: Int, _ dv: Int) {
    r = r.insetBy(dh, dv)
}

public func PtInRect(_ pt: Point, _ r: Rect) -> Bool {
    r.contains(pt)
}

/// MapPt (I-193): maps a point from srcRect's coordinate space into dstRect's.
/// Integer arithmetic truncating toward zero, like the ROM's FixRatio/FixRound path
/// for the values StuntCopter feeds it.
public func MapPt(_ pt: inout Point, _ srcRect: Rect, _ dstRect: Rect) {
    pt.h = (pt.h - srcRect.left) * dstRect.width / srcRect.width + dstRect.left
    pt.v = (pt.v - srcRect.top) * dstRect.height / srcRect.height + dstRect.top
}

public func HiWord(_ x: Int) -> Int { (x >> 16) & 0xFFFF }
public func LoWord(_ x: Int) -> Int { x & 0xFFFF }
