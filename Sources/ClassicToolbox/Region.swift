/// A QuickDraw region: an arbitrary set of pixels, stored as one sorted list of
/// x "inversion points" per scanline ([x0, x1, x2, x3] covers x0..<x1 and x2..<x3).
/// It's a reference type because the Pascal code passes RgnHandles around and
/// relies on CopyRgn vs. handle assignment.
public final class Region {
    public private(set) var top: Int = 0
    /// rows[i] describes scanline `top + i`.
    public private(set) var rows: [[Int]] = []
    public private(set) var rgnBBox: Rect = .zero

    public init() {}

    public convenience init(rect: Rect) {
        self.init()
        setRect(rect)
    }

    public var isEmpty: Bool { rows.isEmpty }

    public func setEmpty() {
        top = 0
        rows = []
        rgnBBox = .zero
    }

    public func setRect(_ r: Rect) {
        guard !r.isEmpty else { setEmpty(); return }
        top = r.top
        rows = Array(repeating: [r.left, r.right], count: r.height)
        rgnBBox = r
    }

    public func copy(from other: Region) {
        top = other.top
        rows = other.rows
        rgnBBox = other.rgnBBox
    }

    public func offset(_ dh: Int, _ dv: Int) {
        guard !rows.isEmpty else { return }
        top += dv
        if dh != 0 {
            for i in rows.indices {
                for j in rows[i].indices { rows[i][j] += dh }
            }
        }
        rgnBBox = rgnBBox.offsetBy(dh, dv)
    }

    /// The inversion points for scanline y (empty if the region doesn't cover it).
    @inline(__always)
    public func spans(atY y: Int) -> [Int] {
        let i = y - top
        guard i >= 0, i < rows.count else { return [] }
        return rows[i]
    }

    public func contains(_ pt: Point) -> Bool {
        let row = spans(atY: pt.v)
        var k = 0
        while k + 1 < row.count {
            if pt.h >= row[k] && pt.h < row[k + 1] { return true }
            k += 2
        }
        return false
    }

    /// Horizontal-only InsetRgn: negative dh grows every span, positive shrinks it.
    public func insetHorizontally(_ dh: Int) {
        guard dh != 0, !rows.isEmpty else { return }
        var newRows: [[Int]] = []
        newRows.reserveCapacity(rows.count)
        for row in rows {
            var out: [Int] = []
            var k = 0
            while k + 1 < row.count {
                let a = row[k] + dh, b = row[k + 1] - dh
                k += 2
                guard a < b else { continue }
                if let last = out.last, a <= last {
                    out[out.count - 1] = max(last, b)   // merge touching/overlapping spans
                } else {
                    out.append(a)
                    out.append(b)
                }
            }
            newRows.append(out)
        }
        assign(top: top, rows: newRows)
    }

    // MARK: Set operations

    public enum Op { case union, difference, intersection, xor }

    /// dst := a <op> b.  dst may be the same object as a or b.
    public static func combine(_ a: Region, _ b: Region, _ op: Op, into dst: Region) {
        let fn: (Bool, Bool) -> Bool
        switch op {
        case .union: fn = { $0 || $1 }
        case .difference: fn = { $0 && !$1 }
        case .intersection: fn = { $0 && $1 }
        case .xor: fn = { $0 != $1 }
        }
        if a.isEmpty && b.isEmpty { dst.setEmpty(); return }
        let lo: Int, hi: Int
        switch (a.isEmpty, b.isEmpty) {
        case (true, _): lo = b.top; hi = b.top + b.rows.count
        case (_, true): lo = a.top; hi = a.top + a.rows.count
        default:
            lo = min(a.top, b.top)
            hi = max(a.top + a.rows.count, b.top + b.rows.count)
        }
        var newRows: [[Int]] = []
        newRows.reserveCapacity(hi - lo)
        for y in lo..<hi {
            newRows.append(combineRow(a.spans(atY: y), b.spans(atY: y), fn))
        }
        dst.assign(top: lo, rows: newRows)
    }

    public static func combineRow(_ a: [Int], _ b: [Int], _ op: (Bool, Bool) -> Bool) -> [Int] {
        if b.isEmpty && op(true, false) && !op(false, false) { return a }   // fast path: a∪∅, a−∅
        var i = 0, j = 0
        var inA = false, inB = false, cur = false
        var out: [Int] = []
        while i < a.count || j < b.count {
            let x = min(i < a.count ? a[i] : Int.max, j < b.count ? b[j] : Int.max)
            while i < a.count && a[i] == x { inA.toggle(); i += 1 }
            while j < b.count && b[j] == x { inB.toggle(); j += 1 }
            let n = op(inA, inB)
            if n != cur {
                out.append(x)
                cur = n
            }
        }
        return out
    }

    /// Installs new rows, trimming empty scanlines and recomputing the bounding box.
    func assign(top newTop: Int, rows newRows: [[Int]]) {
        var first = 0
        var last = newRows.count
        while first < last && newRows[first].isEmpty { first += 1 }
        while last > first && newRows[last - 1].isEmpty { last -= 1 }
        guard first < last else { setEmpty(); return }
        top = newTop + first
        rows = Array(newRows[first..<last])
        var l = Int.max, r = Int.min
        for row in rows where !row.isEmpty {
            l = min(l, row[0])
            r = max(r, row[row.count - 1])
        }
        rgnBBox = Rect(top: top, left: l, bottom: top + rows.count, right: r)
    }

    // MARK: 'RGN ' resource format

    /// Decodes a QuickDraw region record: rgnSize, rgnBBox, then for each scanline where
    /// the shape changes: v, inversion points..., $7FFF; terminated by v = $7FFF.
    public convenience init(qdData d: [UInt8]) throws {
        self.init()
        guard d.count >= 10 else { throw ResourceError.malformed("RGN too short") }
        func i16(_ p: Int) -> Int { Int(Int16(bitPattern: UInt16(d[p]) << 8 | UInt16(d[p + 1]))) }
        let size = i16(0)
        let bbox = Rect(top: i16(2), left: i16(4), bottom: i16(6), right: i16(8))
        if size == 10 { setRect(bbox); return }
        var changes: [(v: Int, points: [Int])] = []
        var p = 10
        while p + 1 < d.count {
            let v = i16(p); p += 2
            if v == 0x7FFF { break }
            var pts: [Int] = []
            while p + 1 < d.count {
                let h = i16(p); p += 2
                if h == 0x7FFF { break }
                pts.append(h)
            }
            changes.append((v, pts.sorted()))
        }
        var newRows: [[Int]] = []
        var cur: [Int] = []
        var c = 0
        for y in bbox.top..<bbox.bottom {
            while c < changes.count && changes[c].v <= y {
                cur = Region.combineRow(cur, changes[c].points, { $0 != $1 })
                c += 1
            }
            newRows.append(cur)
        }
        assign(top: bbox.top, rows: newRows)
    }
}

// MARK: - Toolbox-style region calls

public func NewRgn() -> Region { Region() }
public func DisposeRgn(_ r: Region) { r.setEmpty() }
public func RectRgn(_ rgn: Region, _ r: Rect) { rgn.setRect(r) }
public func SetRectRgn(_ rgn: Region, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
    rgn.setRect(Rect(left: left, top: top, right: right, bottom: bottom))
}
public func CopyRgn(_ src: Region, _ dst: Region) { dst.copy(from: src) }
public func OffsetRgn(_ rgn: Region, _ dh: Int, _ dv: Int) { rgn.offset(dh, dv) }
public func InsetRgn(_ rgn: Region, _ dh: Int, _ dv: Int) {
    precondition(dv == 0, "only horizontal InsetRgn is implemented")
    rgn.insetHorizontally(dh)
}
public func UnionRgn(_ a: Region, _ b: Region, _ dst: Region) { Region.combine(a, b, .union, into: dst) }
public func DiffRgn(_ a: Region, _ b: Region, _ dst: Region) { Region.combine(a, b, .difference, into: dst) }
public func SectRgn(_ a: Region, _ b: Region, _ dst: Region) { Region.combine(a, b, .intersection, into: dst) }
public func PtInRgn(_ pt: Point, _ rgn: Region) -> Bool { rgn.contains(pt) }
