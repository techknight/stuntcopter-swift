import Foundation

/// Pre-rendered 1-bit text: every string a program draws, rendered once with its
/// real bitmap font, plus the font's metrics and character widths (so StringWidth
/// and TextBox wrapping behave exactly as with the font). Lets the port show exact
/// system-font text without shipping the font itself.
///
/// Strings not in the sheet are assembled from the longest entries that match
/// (e.g. "LEVEL " + Apple symbol + digits) — exact for plain text, since
/// QuickDraw draws glyphs independently at their advances.
public struct TextSheet: Sendable {
    public struct Key: Hashable, Sendable {
        public let text: String
        public let face: Int   // TextStyle raw value
    }

    public struct Entry: Sendable {
        public let xOffset: Int       // image column 0 relative to the pen
        public let advance: Int       // pen movement
        public let width: Int
        public let pixels: [UInt8]    // width × (ascent + descent), 1 = black; row 0 = baseline − ascent

        @inline(__always)
        func pixel(_ x: Int, _ y: Int) -> Bool { pixels[y * width + x] != 0 }
    }

    public let ascent: Int
    public let descent: Int
    public let leading: Int
    /// Advance widths by Mac Roman code (plain face); -1 where the font has no glyph.
    public let widths: [Int]
    public private(set) var entries: [Key: Entry]

    public var height: Int { ascent + descent }

    public init(ascent: Int, descent: Int, leading: Int, widths: [Int], entries: [Key: Entry]) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.widths = widths
        self.entries = entries
    }

    public func entry(_ text: Substring, _ face: TextStyle) -> Entry? {
        entries[Key(text: String(text), face: face.rawValue)]
    }

    /// Plain advance of one character (6 for characters the font lacks, like its missing symbol).
    public func advance(of c: Character) -> Int {
        let w = widths[Int(BitmapFont.macRomanCode(c))]
        return w >= 0 ? w : 6
    }

    public func width(of s: String, face: TextStyle) -> Int {
        let bold = face.contains(.bold) ? 1 : 0
        return s.reduce(0) { $0 + advance(of: $1) + bold }
    }

    // MARK: File format ("TXS1", big-endian)

    public init(data d: [UInt8]) throws {
        let r = ByteReader(d)
        guard d.count > 4 + 8 + 512, Array(d[0..<4]) == Array("TXS1".utf8) else {
            throw ResourceError.malformed("text sheet header")
        }
        ascent = r.i16(4); descent = r.i16(6); leading = r.i16(8)
        widths = (0..<256).map { r.i16(12 + 2 * $0) }
        var p = 12 + 512
        let count = r.u16(p); p += 2
        var entries: [Key: Entry] = [:]
        let height = ascent + descent
        for _ in 0..<count {
            let face = r.u8(p)
            let len = r.u8(p + 1)
            let text = macRoman(Array(d[(p + 2)..<(p + 2 + len)]))
            p += 2 + len
            let xOffset = r.i16(p), advance = r.i16(p + 2), width = r.i16(p + 4)
            p += 6
            let rowBytes = (width + 7) / 8
            var pixels = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width where (d[p + y * rowBytes + x / 8] >> (7 - UInt8(x % 8))) & 1 == 1 {
                    pixels[y * width + x] = 1
                }
            }
            p += rowBytes * height
            entries[Key(text: text, face: face)] = Entry(xOffset: xOffset, advance: advance, width: width, pixels: pixels)
        }
        self.entries = entries
    }

    public func encoded() -> [UInt8] {
        var out = Array("TXS1".utf8)
        func w16(_ v: Int) { out.append(UInt8((v >> 8) & 0xFF)); out.append(UInt8(v & 0xFF)) }
        w16(ascent); w16(descent); w16(leading); w16(0)
        for v in widths { w16(v) }
        w16(entries.count)
        // Sorted, so regenerating an unchanged sheet gives identical bytes.
        for (key, e) in entries.sorted(by: { ($0.key.face, $0.key.text) < ($1.key.face, $1.key.text) }) {
            let bytes = [UInt8](key.text.data(using: .macOSRoman) ?? Data())
            out.append(UInt8(key.face)); out.append(UInt8(bytes.count)); out += bytes
            w16(e.xOffset); w16(e.advance); w16(e.width)
            let rowBytes = (e.width + 7) / 8
            for y in 0..<height {
                var row = [UInt8](repeating: 0, count: rowBytes)
                for x in 0..<e.width where e.pixel(x, y) { row[x / 8] |= UInt8(0x80 >> (x % 8)) }
                out += row
            }
        }
        return out
    }
}

extension TextSheet {
    /// Renders `strings` (and each `textBoxes` item wrapped into lines, as TextBox
    /// would) with `font`. This is the only place the real font is needed.
    @MainActor
    public static func build(font: BitmapFont, strings: [(String, TextStyle)],
                             textBoxes: [(text: String, width: Int)]) -> TextSheet {
        let qd = QuickDraw(port: GrafPort(size: Rect(top: 0, left: 0, bottom: 1, right: 1)))
        qd.textSource = .font(font)
        var all = strings
        for box in textBoxes {
            for line in qd.wrap(box.text, width: box.width) where !line.isEmpty { all.append((line, [])) }
        }
        var entries: [Key: Entry] = [:]
        let height = font.ascent + font.descent
        for (text, face) in all where !text.isEmpty {
            let key = Key(text: text, face: face.rawValue)
            guard entries[key] == nil else { continue }
            let origin = 16
            let w = font.width(of: text, face: face) + 2 * origin
            let port = GrafPort(size: Rect(top: 0, left: 0, bottom: height, right: w))
            qd.SetPort(port)
            qd.TextFace(face)
            qd.MoveTo(origin, font.ascent)
            qd.DrawString(text)
            let bm = port.portBits
            let inked = (0..<w).filter { x in (0..<height).contains { bm.pixel(x, $0) != 0 } }
            let lo = inked.first ?? origin, hi = (inked.last ?? origin - 1) + 1
            var pixels = [UInt8](repeating: 0, count: (hi - lo) * height)
            for y in 0..<height {
                for x in lo..<hi { pixels[y * (hi - lo) + (x - lo)] = bm.pixel(x, y) }
            }
            entries[key] = Entry(xOffset: lo - origin, advance: port.pnLoc.h - origin, width: hi - lo, pixels: pixels)
        }
        let widths = (0..<256).map { code -> Int in
            let c = Character(macRoman([UInt8(code)]))
            return font.hasGlyph(for: c) ? font.glyph(for: c).advance : -1
        }
        return TextSheet(ascent: font.ascent, descent: font.descent, leading: font.leading,
                         widths: widths, entries: entries)
    }
}

/// Where QuickDraw gets text from.
public enum TextSource: Sendable {
    case none
    case font(BitmapFont)
    case sheet(TextSheet)

    public var ascent: Int {
        switch self { case .font(let f): f.ascent; case .sheet(let s): s.ascent; case .none: 12 }
    }
    public var descent: Int {
        switch self { case .font(let f): f.descent; case .sheet(let s): s.descent; case .none: 3 }
    }
    public var leading: Int {
        switch self { case .font(let f): f.leading; case .sheet(let s): s.leading; case .none: 1 }
    }
    public func width(of s: String, face: TextStyle) -> Int {
        switch self {
        case .font(let f): f.width(of: s, face: face)
        case .sheet(let sheet): sheet.width(of: s, face: face)
        case .none: 0
        }
    }
}
