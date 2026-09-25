import Foundation

/// A classic Macintosh bitmap font, decoded from a 'FONT' resource
/// (Inside Macintosh I-227). The port doesn't ship one: `rsrc-tool text-sheet` uses
/// Chicago 12 from a System 6 disk (Tools/extract_system_font.py) to pre-render the
/// game's text into a TextSheet.
public struct BitmapFont: Sendable {
    public struct Glyph: Sendable {
        /// Width of the glyph image in pixels.
        public let width: Int
        /// Horizontal pen movement (the character width).
        public let advance: Int
        /// Where the image starts relative to the pen (kernMax + offset).
        public let xOffset: Int
        /// Rows from the top of the font rectangle (baseline − ascent) downward.
        let rows: [[Bool]]

        @inline(__always)
        public func pixel(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < rows.count, x >= 0, x < width else { return false }
            return rows[y][x]
        }
    }

    public let ascent: Int
    public let descent: Int
    public let leading: Int
    public let widMax: Int
    /// Glyphs indexed by Mac Roman character code.
    let glyphs: [UInt8: Glyph]
    let missing: Glyph

    public func glyph(for c: Character) -> Glyph {
        glyphs[BitmapFont.macRomanCode(c)] ?? missing
    }

    public func hasGlyph(for c: Character) -> Bool {
        glyphs[BitmapFont.macRomanCode(c)] != nil
    }

    public func width(of s: String, face: TextStyle) -> Int {
        let bold = face.contains(.bold) ? 1 : 0
        return s.reduce(0) { $0 + glyph(for: $1).advance + bold }
    }

    static func macRomanCode(_ c: Character) -> UInt8 {
        if let a = c.asciiValue { return a }
        return String(c).data(using: .macOSRoman)?.first ?? 0
    }

    /// Decodes a 'FONT'/'NFNT' resource.
    public init(fontResource d: [UInt8]) throws {
        let r = ByteReader(d)
        guard d.count >= 26 else { throw ResourceError.malformed("FONT header") }
        let firstChar = r.i16(2), lastChar = r.i16(4)
        widMax = r.i16(6)
        let kernMax = r.i16(8)
        let fRectHeight = r.i16(14)
        let owTLoc = r.i16(16)
        ascent = r.i16(18)
        descent = r.i16(20)
        leading = r.i16(22)
        let rowWords = r.i16(24)
        let rowBytes = rowWords * 2
        let imageStart = 26
        let locStart = imageStart + rowBytes * fRectHeight
        let owStart = 16 + owTLoc * 2
        let n = lastChar - firstChar + 2   // characters plus the missing-symbol glyph
        guard owStart + 2 * (n + 1) <= d.count else { throw ResourceError.malformed("FONT tables") }

        func bit(_ x: Int, _ y: Int) -> Bool {
            (d[imageStart + y * rowBytes + x / 8] >> (7 - UInt8(x % 8))) & 1 != 0
        }

        func makeGlyph(_ i: Int) -> Glyph? {
            let ow = r.u16(owStart + 2 * i)
            guard ow != 0xFFFF else { return nil }
            let loc = r.i16(locStart + 2 * i), next = r.i16(locStart + 2 * (i + 1))
            let w = max(0, next - loc)
            let rows = (0..<fRectHeight).map { y in (0..<w).map { bit(loc + $0, y) } }
            return Glyph(width: w, advance: ow & 0xFF, xOffset: kernMax + (ow >> 8), rows: rows)
        }

        var glyphs: [UInt8: Glyph] = [:]
        for c in firstChar...lastChar {
            if let g = makeGlyph(c - firstChar) { glyphs[UInt8(c)] = g }
        }
        self.glyphs = glyphs
        missing = makeGlyph(n - 1) ?? Glyph(width: 0, advance: widMax, xOffset: 0, rows: [])
    }

}
