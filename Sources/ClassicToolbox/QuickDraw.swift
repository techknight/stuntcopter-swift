import Foundation

/// The subset of QuickDraw that StuntCopter uses, as an instance with its own
/// "thePort", randSeed and tick clock so ported code can call the Toolbox the way
/// the Pascal did. Subclass it (the game does) to get unqualified calls.
@MainActor
open class QuickDraw {
    public private(set) var thePort: GrafPort
    public var randSeed: Int32 = 1          // InitGraf sets randSeed to 1
    /// Where text comes from: a pre-rendered TextSheet (the game), or a real bitmap
    /// font (only the TextSheet generator needs one).
    public var textSource: TextSource = .none
    /// Characters DrawString couldn't find (drawn as missing-symbol boxes).
    public private(set) var textMisses = Set<Character>()
    /// Returns TickCount (1/60 s). Replaceable for tests.
    public var tickSource: () -> Int

    public init(port: GrafPort) {
        thePort = port
        let start = DispatchTime.now().uptimeNanoseconds
        tickSource = { Int((DispatchTime.now().uptimeNanoseconds - start) * 60 / 1_000_000_000) }
    }

    // MARK: Ports

    public func SetPort(_ port: GrafPort) { thePort = port }
    public func GetPort() -> GrafPort { thePort }
    public func SetPortBits(_ bm: BitMap) { thePort.portBits = bm }
    public func ClipRect(_ r: Rect) { thePort.clipRgn = Region(rect: r) }
    public func TextFace(_ face: TextStyle) { thePort.txFace = face }
    public func TextFont(_ id: Int) {}      // only the system font exists here
    public func TickCount() -> Int { tickSource() }

    /// QuickDraw's Random (I-194): Park–Miller "minimal standard" generator,
    /// returning the low word of the seed as a signed integer in -32767..32767.
    public func Random() -> Int {
        randSeed = Int32((Int64(randSeed) * 16807) % 0x7FFF_FFFF)
        var r = Int(Int16(truncatingIfNeeded: randSeed))
        if r == -32768 { r = 0 }
        return r
    }

    // MARK: Clipping

    /// Calls body(y, x0, x1) for every horizontal run of `rect` that survives clipping
    /// to `dst`'s bounds, the port's clipRgn/visRgn (when `portClip`), and `mask`.
    @inline(__always)
    func forEachSpan(_ rect: Rect, in dst: BitMap, portClip: Bool, mask: Region?,
                     _ body: (Int, Int, Int) -> Void) {
        var r = rect.intersection(dst.bounds)
        let clip = portClip ? thePort.clipRgn : nil
        let vis = portClip ? thePort.visRgn : nil
        if let c = clip { r = r.intersection(c.rgnBBox) }
        if let v = vis { r = r.intersection(v.rgnBBox) }
        if let m = mask { r = r.intersection(m.rgnBBox) }
        guard !r.isEmpty else { return }
        let and: (Bool, Bool) -> Bool = { $0 && $1 }
        for y in r.top..<r.bottom {
            var spans = [r.left, r.right]
            if let c = clip { spans = Region.combineRow(spans, c.spans(atY: y), and) }
            if let v = vis, !spans.isEmpty { spans = Region.combineRow(spans, v.spans(atY: y), and) }
            if let m = mask, !spans.isEmpty { spans = Region.combineRow(spans, m.spans(atY: y), and) }
            var k = 0
            while k + 1 < spans.count {
                body(y, spans[k], spans[k + 1])
                k += 2
            }
        }
    }

    // MARK: CopyBits (I-188)

    public func CopyBits(_ src: BitMap, _ dst: BitMap, _ srcRect: Rect, _ dstRect: Rect,
                         _ mode: TransferMode, _ maskRgn: Region?) {
        guard !srcRect.isEmpty, !dstRect.isEmpty else { return }
        let sw = srcRect.width, sh = srcRect.height
        let dw = dstRect.width, dh = dstRect.height
        let same = sw == dw && sh == dh
        forEachSpan(dstRect, in: dst, portClip: dst === thePort.portBits, mask: maskRgn) { y, x0, x1 in
            let sy = srcRect.top + (same ? y - dstRect.top : (y - dstRect.top) * sh / dh)
            guard sy >= src.bounds.top, sy < src.bounds.bottom else { return }
            for x in x0..<x1 {
                let sx = srcRect.left + (same ? x - dstRect.left : (x - dstRect.left) * sw / dw)
                guard sx >= src.bounds.left, sx < src.bounds.right else { continue }
                let s = src.pixels[src.index(sx, sy)]
                let di = dst.index(x, y)
                switch mode {
                case .srcCopy: dst.pixels[di] = s
                case .srcOr: dst.pixels[di] |= s
                case .srcXor: dst.pixels[di] ^= s
                case .srcBic: if s != 0 { dst.pixels[di] = 0 }
                }
            }
        }
        dst.markChanged()
    }

    // MARK: Rectangles (I-174)

    func fill(_ r: Rect, _ pat: Pattern, mask: Region? = nil) {
        let bm = thePort.portBits
        let ox = bm.bounds.left, oy = bm.bounds.top
        forEachSpan(r, in: bm, portClip: true, mask: mask) { y, x0, x1 in
            for x in x0..<x1 { bm.pixels[bm.index(x, y)] = pat.bit(x - ox, y - oy) }
        }
        bm.markChanged()
    }

    func invert(_ r: Rect, mask: Region? = nil) {
        let bm = thePort.portBits
        forEachSpan(r, in: bm, portClip: true, mask: mask) { y, x0, x1 in
            for x in x0..<x1 { bm.pixels[bm.index(x, y)] ^= 1 }
        }
        bm.markChanged()
    }

    public func EraseRect(_ r: Rect) { fill(r, thePort.bkPat) }
    public func PaintRect(_ r: Rect) { fill(r, .black) }
    public func FillRect(_ r: Rect, _ pat: Pattern) { fill(r, pat) }
    public func InvertRect(_ r: Rect) { invert(r) }

    public func FrameRect(_ r: Rect) {
        guard !r.isEmpty else { return }
        let rgn = Region(rect: r)
        DiffRgn(rgn, Region(rect: r.insetBy(1, 1)), rgn)
        fill(r, .black, mask: rgn)
    }

    // MARK: Regions

    public func FillRgn(_ rgn: Region, _ pat: Pattern) { fill(rgn.rgnBBox, pat, mask: rgn) }
    public func PaintRgn(_ rgn: Region) { fill(rgn.rgnBBox, .black, mask: rgn) }
    public func EraseRgn(_ rgn: Region) { fill(rgn.rgnBBox, thePort.bkPat, mask: rgn) }
    public func InvertRgn(_ rgn: Region) { invert(rgn.rgnBBox, mask: rgn) }

    // MARK: Rounded rectangles (I-177)

    /// The pixel area of a rounded rectangle whose corners are quarter-ellipses of
    /// ovalWidth × ovalHeight.
    public static func roundRectRegion(_ r: Rect, _ ovalWidth: Int, _ ovalHeight: Int) -> Region {
        let rgn = Region()
        guard !r.isEmpty else { return rgn }
        let ow = min(ovalWidth, r.width), oh = min(ovalHeight, r.height)
        guard ow > 1, oh > 1 else { rgn.setRect(r); return rgn }
        let a = Double(ow) / 2, b = Double(oh) / 2
        var rows: [[Int]] = []
        for y in r.top..<r.bottom {
            let fromTop = y - r.top, fromBottom = r.bottom - 1 - y
            let d = min(fromTop, fromBottom)
            var inset = 0
            if Double(d) < b {
                let dy = b - (Double(d) + 0.5)
                let dx = a * (1 - (dy * dy) / (b * b)).squareRoot()
                inset = Int((a - dx).rounded())
            }
            rows.append([r.left + inset, r.right - inset])
        }
        rgn.assign(top: r.top, rows: rows)
        return rgn
    }

    public func FrameRoundRect(_ r: Rect, _ ow: Int, _ oh: Int) {
        let outer = QuickDraw.roundRectRegion(r, ow, oh)
        let inner = QuickDraw.roundRectRegion(r.insetBy(1, 1), max(0, ow - 2), max(0, oh - 2))
        DiffRgn(outer, inner, outer)
        PaintRgn(outer)
    }

    public func PaintRoundRect(_ r: Rect, _ ow: Int, _ oh: Int) { PaintRgn(QuickDraw.roundRectRegion(r, ow, oh)) }
    public func EraseRoundRect(_ r: Rect, _ ow: Int, _ oh: Int) { EraseRgn(QuickDraw.roundRectRegion(r, ow, oh)) }
    public func InvertRoundRect(_ r: Rect, _ ow: Int, _ oh: Int) { InvertRgn(QuickDraw.roundRectRegion(r, ow, oh)) }

    public func FrameOval(_ r: Rect) { FrameRoundRect(r, r.width, r.height) }
    public func PaintOval(_ r: Rect) { PaintRoundRect(r, r.width, r.height) }
    public func EraseOval(_ r: Rect) { EraseRoundRect(r, r.width, r.height) }

    // MARK: Lines (I-171), 1×1 black pen

    public func MoveTo(_ h: Int, _ v: Int) { thePort.pnLoc = Point(h: h, v: v) }
    public func Move(_ dh: Int, _ dv: Int) { thePort.pnLoc.h += dh; thePort.pnLoc.v += dv }

    public func LineTo(_ h: Int, _ v: Int) {
        var x = thePort.pnLoc.h, y = thePort.pnLoc.v
        let dx = abs(h - x), dy = -abs(v - y)
        let sx = x < h ? 1 : -1, sy = y < v ? 1 : -1
        var err = dx + dy
        let bm = thePort.portBits
        while true {
            forEachSpan(Rect(top: y, left: x, bottom: y + 1, right: x + 1), in: bm, portClip: true, mask: nil) { py, px, _ in
                bm.pixels[bm.index(px, py)] = 1
            }
            if x == h && y == v { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
        bm.markChanged()
        thePort.pnLoc = Point(h: h, v: v)
    }

    // MARK: Pictures (I-190)

    /// DrawPicture: draws each bitmap op, mapping picture space (picFrame) onto dstRect.
    public func DrawPicture(_ pic: Picture, _ dstRect: Rect) {
        for op in pic.ops {
            var d = op.dstRect
            OffsetRect(&d, dstRect.left - pic.picFrame.left, dstRect.top - pic.picFrame.top)
            if dstRect.width != pic.picFrame.width || dstRect.height != pic.picFrame.height {
                // Scale the op's rect proportionally (not needed by StuntCopter).
                d = Rect(left: dstRect.left + (op.dstRect.left - pic.picFrame.left) * dstRect.width / pic.picFrame.width,
                         top: dstRect.top + (op.dstRect.top - pic.picFrame.top) * dstRect.height / pic.picFrame.height,
                         right: dstRect.left + (op.dstRect.right - pic.picFrame.left) * dstRect.width / pic.picFrame.width,
                         bottom: dstRect.top + (op.dstRect.bottom - pic.picFrame.top) * dstRect.height / pic.picFrame.height)
            }
            CopyBits(op.bitmap, thePort.portBits, op.srcRect, d, op.mode == 0 ? .srcCopy : .srcOr, nil)
        }
    }

    // MARK: Text (I-171)

    public var textAscent: Int { textSource.ascent }
    public var textDescent: Int { textSource.descent }
    public var textLeading: Int { textSource.leading }

    public func StringWidth(_ s: String) -> Int { textSource.width(of: s, face: thePort.txFace) }
    public func CharWidth(_ c: Character) -> Int { textSource.width(of: String(c), face: thePort.txFace) }

    /// DrawString in srcOr mode at the pen location (the baseline); advances the pen.
    public func DrawString(_ s: String) {
        switch textSource {
        case .font(let font): drawString(s, font)
        case .sheet(let sheet): drawString(s, sheet)
        case .none: thePort.pnLoc.h += StringWidth(s)
        }
    }

    /// Plots a pre-rendered string's pixels at the pen (srcOr semantics).
    func plot(_ e: TextSheet.Entry, _ sheet: TextSheet) {
        let bm = thePort.portBits
        let left = thePort.pnLoc.h + e.xOffset, top = thePort.pnLoc.v - sheet.ascent
        forEachSpan(Rect(top: top, left: left, bottom: top + sheet.height, right: left + e.width),
                    in: bm, portClip: true, mask: nil) { y, x0, x1 in
            for x in x0..<x1 where e.pixel(x - left, y - top) {
                let i = bm.index(x, y)
                switch thePort.txMode {
                case .srcXor: bm.pixels[i] ^= 1
                case .srcBic: bm.pixels[i] = 0
                default: bm.pixels[i] = 1
                }
            }
        }
        thePort.pnLoc.h += e.advance
    }

    /// DrawString from a TextSheet: the longest pre-rendered piece at each point.
    func drawString(_ s: String, _ sheet: TextSheet) {
        let face = thePort.txFace
        var rest = Substring(s)
        while let first = rest.first {
            var found: (TextSheet.Entry, Int)?
            for len in stride(from: rest.count, through: 1, by: -1) {
                if let e = sheet.entry(rest.prefix(len), face) { found = (e, len); break }
            }
            if let (e, len) = found {
                plot(e, sheet)
                rest = rest.dropFirst(len)
            } else {
                // Not in the sheet: QuickDraw's missing symbol, an outlined box.
                textMisses.insert(first)
                let h = thePort.pnLoc.h, v = thePort.pnLoc.v
                FrameRect(Rect(top: v - 9, left: h, bottom: v, right: h + 5))
                thePort.pnLoc = Point(h: h + sheet.width(of: String(first), face: face), v: v)
                rest = rest.dropFirst()
            }
        }
        thePort.portBits.markChanged()
    }

    /// DrawString with a real bitmap font (used to generate TextSheets).
    func drawString(_ s: String, _ font: BitmapFont) {
        let bm = thePort.portBits
        let face = thePort.txFace
        let boldExtra = face.contains(.bold) ? 1 : 0
        let startH = thePort.pnLoc.h
        let base = thePort.pnLoc.v
        var h = startH
        var descenderXs = Set<Int>()   // columns with glyph pixels below the baseline
        for ch in s {
            let g = font.glyph(for: ch)
            // QuickDraw bold: the glyph is drawn again one pixel to the right.
            let left = h + g.xOffset
            if face.contains(.underline) {
                // Anything below the baseline counts as a descender (matches QuickDraw's output).
                for x in 0..<(g.width + boldExtra) {
                    for y in font.ascent..<(font.ascent + font.descent)
                    where g.pixel(x, y) || (boldExtra == 1 && g.pixel(x - 1, y)) {
                        descenderXs.insert(left + x)
                        break
                    }
                }
            }
            let glyphRect = Rect(top: base - font.ascent, left: left, bottom: base + font.descent,
                                 right: left + g.width + boldExtra)
            forEachSpan(glyphRect, in: bm, portClip: true, mask: nil) { y, x0, x1 in
                let gy = y - (base - font.ascent)
                for x in x0..<x1 {
                    var on = g.pixel(x - left, gy)
                    if boldExtra == 1 && !on { on = g.pixel(x - left - 1, gy) }
                    if on {
                        let i = bm.index(x, y)
                        switch thePort.txMode {
                        case .srcXor: bm.pixels[i] ^= 1
                        case .srcBic: bm.pixels[i] = 0
                        default: bm.pixels[i] = 1
                        }
                    }
                }
            }
            h += g.advance + boldExtra
        }
        if face.contains(.underline) {
            // The underline leaves a one-pixel gap around descenders.
            let y = base + 1
            forEachSpan(Rect(top: y, left: startH, bottom: y + 1, right: h), in: bm, portClip: true, mask: nil) { py, x0, x1 in
                for x in x0..<x1 where !descenderXs.contains(x) && !descenderXs.contains(x - 1) && !descenderXs.contains(x + 1) {
                    bm.pixels[bm.index(x, py)] = 1
                }
            }
        }
        bm.markChanged()
        thePort.pnLoc.h = h
    }

    /// TextBox (I-388): erases the box, then draws word-wrapped, left-justified text
    /// in it, honoring CRs.
    public func TextBox(_ text: String, _ box: Rect) {
        EraseRect(box)
        let lineHeight = textAscent + textDescent + textLeading
        var v = box.top + textAscent
        for line in wrap(text, width: box.width) {
            if v - textAscent >= box.bottom { break }
            MoveTo(box.left + 1, v)   // TextEdit starts lines one pixel in (matches the original)
            DrawString(line)
            v += lineHeight
        }
    }

    /// Splits text into lines no wider than `width` (counting each word's trailing
    /// spaces), breaking at spaces and CRs.
    public func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        for para in text.split(separator: "\r", omittingEmptySubsequences: false) {
            var line = ""
            var i = para.startIndex
            while i < para.endIndex {
                // take a word plus its trailing spaces
                var j = i
                while j < para.endIndex && para[j] != " " { j = para.index(after: j) }
                while j < para.endIndex && para[j] == " " { j = para.index(after: j) }
                let word = String(para[i..<j])
                let candidate = line + word
                // Like TextEdit, a word is measured with its trailing spaces: in the About
                // box "…$18.00 plus" is exactly the box width, and the original still wraps.
                if !line.isEmpty && StringWidth(candidate) > width {
                    lines.append(line)
                    line = word
                } else {
                    line = candidate
                }
                i = j
            }
            lines.append(line)
        }
        return lines
    }
}
