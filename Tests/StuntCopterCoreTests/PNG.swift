import Foundation

// A small, dependency-free PNG codec so the tests run wherever Swift does (ImageIO
// and CoreGraphics are Apple-only). Reads non-interlaced PNGs of any colour type;
// writes 8-bit grayscale with uncompressed deflate blocks.

struct PNGError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// A decoded image as 8-bit RGBA, rows top to bottom.
struct RGBAImage {
    let width: Int, height: Int
    var rgba: [UInt8]

    /// Luminance (Rec. 601) composited over black, the way drawing into a zeroed
    /// DeviceGray CGContext produced it.
    var gray: [UInt8] {
        (0..<width * height).map { i in
            let r = Int(rgba[4 * i]), g = Int(rgba[4 * i + 1]), b = Int(rgba[4 * i + 2]), a = Int(rgba[4 * i + 3])
            return UInt8((299 * r + 587 * g + 114 * b) * a / (1000 * 255))
        }
    }
}

enum PNG {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func decode(contentsOf url: URL) throws -> RGBAImage {
        try decode([UInt8](Data(contentsOf: url)))
    }

    static func decode(_ bytes: [UInt8]) throws -> RGBAImage {
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw PNGError("not a PNG") }
        func be32(_ i: Int) -> Int {
            Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
        }
        var width = 0, height = 0, depth = 0, colorType = 0
        var palette: [UInt8] = [], transparency: [UInt8] = [], idat: [UInt8] = []
        var i = 8
        while i + 8 <= bytes.count {
            let length = be32(i), type = String(decoding: bytes[i + 4..<i + 8], as: UTF8.self)
            guard i + 12 + length <= bytes.count else { throw PNGError("truncated \(type) chunk") }
            let body = bytes[i + 8..<i + 8 + length]
            guard crc32(bytes[i + 4..<i + 8 + length]) == UInt32(be32(i + 8 + length)) else {
                throw PNGError("bad CRC in \(type) chunk")
            }
            switch type {
            case "IHDR":
                width = be32(i + 8); height = be32(i + 12)
                depth = Int(body[body.startIndex + 8]); colorType = Int(body[body.startIndex + 9])
                guard body[body.startIndex + 12] == 0 else { throw PNGError("interlaced PNGs are not supported") }
            case "PLTE": palette = Array(body)
            case "tRNS": transparency = Array(body)
            case "IDAT": idat += body
            default: break
            }
            i += 12 + length
            if type == "IEND" { break }
        }
        let channels: Int
        switch colorType {
        case 0: channels = 1   // gray
        case 2: channels = 3   // RGB
        case 3: channels = 1   // palette index
        case 4: channels = 2   // gray + alpha
        case 6: channels = 4   // RGBA
        default: throw PNGError("unknown colour type \(colorType)")
        }
        guard width > 0, height > 0, [1, 2, 4, 8, 16].contains(depth) else { throw PNGError("bad IHDR") }

        // Undo the per-row filters (PNG spec §9).
        let data = try zlibDecompress(idat)
        let bpp = max(1, channels * depth / 8)   // bytes per complete pixel, for filtering
        let stride = (width * channels * depth + 7) / 8
        guard data.count >= height * (stride + 1) else { throw PNGError("image data too short") }
        var raw = [UInt8](repeating: 0, count: height * stride)
        for y in 0..<height {
            let filter = data[y * (stride + 1)], src = y * (stride + 1) + 1, row = y * stride
            for x in 0..<stride {
                let a = x >= bpp ? Int(raw[row + x - bpp]) : 0
                let b = y > 0 ? Int(raw[row - stride + x]) : 0
                let c = x >= bpp && y > 0 ? Int(raw[row - stride + x - bpp]) : 0
                let predictor: Int
                switch filter {
                case 0: predictor = 0
                case 1: predictor = a
                case 2: predictor = b
                case 3: predictor = (a + b) / 2
                case 4:
                    let p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    predictor = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
                default: throw PNGError("unknown filter \(filter) on row \(y)")
                }
                raw[row + x] = UInt8(truncatingIfNeeded: Int(data[src + x]) + predictor)
            }
        }

        // Expand samples to 8-bit RGBA.
        func sample(_ y: Int, _ n: Int) -> Int {   // n-th sample of row y, at its own depth
            let row = y * stride
            switch depth {
            case 16: return Int(raw[row + 2 * n]) << 8 | Int(raw[row + 2 * n + 1])
            case 8: return Int(raw[row + n])
            default:
                let bit = n * depth, shift = 8 - depth - bit % 8
                return Int(raw[row + bit / 8] >> shift) & (1 << depth - 1)
            }
        }
        let maxValue = (1 << depth) - 1
        func to8(_ v: Int) -> UInt8 { UInt8(v * 255 / maxValue) }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = 4 * (y * width + x), s = x * channels
                switch colorType {
                case 0:
                    let v = sample(y, s)
                    rgba[o] = to8(v); rgba[o + 1] = rgba[o]; rgba[o + 2] = rgba[o]
                    if transparency.count >= 2, v == (Int(transparency[0]) << 8 | Int(transparency[1])) & maxValue {
                        rgba[o + 3] = 0
                    }
                case 2:
                    let r = sample(y, s), g = sample(y, s + 1), b = sample(y, s + 2)
                    rgba[o] = to8(r); rgba[o + 1] = to8(g); rgba[o + 2] = to8(b)
                    if transparency.count >= 6,
                       [r, g, b] == (0..<3).map({ Int(transparency[2 * $0]) << 8 | Int(transparency[2 * $0 + 1]) }) {
                        rgba[o + 3] = 0
                    }
                case 3:
                    let p = sample(y, s)
                    guard 3 * p + 2 < palette.count else { throw PNGError("palette index \(p) out of range") }
                    rgba[o] = palette[3 * p]; rgba[o + 1] = palette[3 * p + 1]; rgba[o + 2] = palette[3 * p + 2]
                    if p < transparency.count { rgba[o + 3] = transparency[p] }
                case 4:
                    rgba[o] = to8(sample(y, s)); rgba[o + 1] = rgba[o]; rgba[o + 2] = rgba[o]
                    rgba[o + 3] = to8(sample(y, s + 1))
                default:
                    for k in 0..<4 { rgba[o + k] = to8(sample(y, s + k)) }
                }
            }
        }
        return RGBAImage(width: width, height: height, rgba: rgba)
    }

    /// 8-bit grayscale PNG, deflated with stored (uncompressed) blocks.
    static func encodeGray(width: Int, height: Int, gray: [UInt8]) -> Data {
        var scanlines = [UInt8]()
        scanlines.reserveCapacity(height * (width + 1))
        for y in 0..<height {
            scanlines.append(0)   // filter: none
            scanlines += gray[y * width..<(y + 1) * width]
        }
        var z: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let n = min(65_535, scanlines.count - offset)
            z.append(offset + n == scanlines.count ? 1 : 0)   // BFINAL, BTYPE = stored
            z += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8(~n >> 8 & 0xFF)]
            z += scanlines[offset..<offset + n]
            offset += n
        } while offset < scanlines.count
        z += bigEndian(adler32(scanlines))

        var png = signature
        func chunk(_ type: String, _ body: [UInt8]) {
            let typed = Array(type.utf8) + body
            png += bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed[...]))
        }
        chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 0, 0, 0, 0])
        chunk("IDAT", z)
        chunk("IEND", [])
        return Data(png)
    }

    private static func bigEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 != 0 ? 0xEDB8_8320 ^ c >> 1 : c >> 1 }
    }

    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        ~bytes.reduce(~UInt32(0)) { c, b in crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ c >> 8 }
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for chunk in stride(from: 0, to: bytes.count, by: 5552) {   // largest run without overflow
            for byte in bytes[chunk..<min(chunk + 5552, bytes.count)] { a += UInt32(byte); b += a }
            a %= 65_521; b %= 65_521
        }
        return b << 16 | a
    }
}

// MARK: - zlib / DEFLATE (RFC 1950, RFC 1951)

func zlibDecompress(_ z: [UInt8]) throws -> [UInt8] {
    guard z.count >= 6, z[0] & 0x0F == 8, (Int(z[0]) << 8 | Int(z[1])) % 31 == 0 else {
        throw PNGError("bad zlib header")
    }
    guard z[1] & 0x20 == 0 else { throw PNGError("zlib preset dictionaries are not supported") }
    var inflater = Inflater(z, start: 2)
    let out = try inflater.run()
    let p = inflater.byteAligned()
    guard p + 4 <= z.count else { throw PNGError("missing Adler-32") }
    let stored = UInt32(z[p]) << 24 | UInt32(z[p + 1]) << 16 | UInt32(z[p + 2]) << 8 | UInt32(z[p + 3])
    guard stored == PNG.adler32(out) else { throw PNGError("Adler-32 mismatch") }
    return out
}

/// Canonical Huffman decoding in the style of zlib's puff.c: per-length code counts
/// plus symbols sorted by code.
private struct Huffman {
    var counts = [Int](repeating: 0, count: 16)
    var symbols: [Int]

    init(lengths: [Int]) throws {
        for l in lengths { counts[l] += 1 }
        counts[0] = 0
        var left = 1   // over-subscribed code sets are invalid; incomplete ones are allowed
        for len in 1..<16 {
            left = left << 1 - counts[len]
            guard left >= 0 else { throw PNGError("over-subscribed Huffman code") }
        }
        var offsets = [Int](repeating: 0, count: 16)
        for len in 1..<15 { offsets[len + 1] = offsets[len] + counts[len] }
        symbols = [Int](repeating: 0, count: lengths.count)
        for (sym, len) in lengths.enumerated() where len != 0 {
            symbols[offsets[len]] = sym
            offsets[len] += 1
        }
    }
}

private struct Inflater {
    let input: [UInt8]
    var pos: Int
    var bitBuffer = 0, bitCount = 0
    var out: [UInt8] = []

    init(_ input: [UInt8], start: Int) { self.input = input; pos = start }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                             35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                              3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                           257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let fixedLengths = try! Huffman(lengths: (0..<288).map { $0 < 144 ? 8 : $0 < 256 ? 9 : $0 < 280 ? 7 : 8 })
    static let fixedDistances = try! Huffman(lengths: [Int](repeating: 5, count: 30))

    mutating func bits(_ n: Int) throws -> Int {
        while bitCount < n {
            guard pos < input.count else { throw PNGError("deflate stream ends early") }
            bitBuffer |= Int(input[pos]) << bitCount
            pos += 1; bitCount += 8
        }
        let v = bitBuffer & (1 << n - 1)
        bitBuffer >>= n; bitCount -= n
        return v
    }

    /// Where the byte after the deflate stream starts.
    func byteAligned() -> Int { pos - bitCount / 8 }

    mutating func decode(_ h: Huffman) throws -> Int {
        var code = 0, first = 0, index = 0
        for len in 1..<16 {
            code |= try bits(1)
            let count = h.counts[len]
            if code - count < first { return h.symbols[index + code - first] }
            index += count; first += count
            first <<= 1; code <<= 1
        }
        throw PNGError("invalid Huffman code")
    }

    mutating func run() throws -> [UInt8] {
        var final = 0
        repeat {
            final = try bits(1)
            switch try bits(2) {
            case 0: try stored()
            case 1: try codes(Inflater.fixedLengths, Inflater.fixedDistances)
            case 2:
                let (lengths, distances) = try dynamicTables()
                try codes(lengths, distances)
            default: throw PNGError("invalid deflate block type")
            }
        } while final == 0
        return out
    }

    mutating func stored() throws {
        bitBuffer = 0; bitCount = 0   // skip to the byte boundary
        guard pos + 4 <= input.count else { throw PNGError("stored block header truncated") }
        let len = Int(input[pos]) | Int(input[pos + 1]) << 8
        let nlen = Int(input[pos + 2]) | Int(input[pos + 3]) << 8
        guard len == ~nlen & 0xFFFF else { throw PNGError("stored block length check failed") }
        pos += 4
        guard pos + len <= input.count else { throw PNGError("stored block truncated") }
        out += input[pos..<pos + len]
        pos += len
    }

    mutating func dynamicTables() throws -> (Huffman, Huffman) {
        let nlen = try bits(5) + 257, ndist = try bits(5) + 1, ncode = try bits(4) + 4
        guard nlen <= 286, ndist <= 30 else { throw PNGError("bad dynamic block counts") }
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode { codeLengths[order[i]] = try bits(3) }
        let lencode = try Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        while lengths.count < nlen + ndist {
            let sym = try decode(lencode)
            switch sym {
            case 0..<16: lengths.append(sym)
            case 16:
                guard let prev = lengths.last else { throw PNGError("repeat with no previous length") }
                lengths += repeatElement(prev, count: 3 + (try bits(2)))
            case 17: lengths += repeatElement(0, count: 3 + (try bits(3)))
            default: lengths += repeatElement(0, count: 11 + (try bits(7)))
            }
        }
        guard lengths.count == nlen + ndist else { throw PNGError("code lengths overrun") }
        guard lengths[256] != 0 else { throw PNGError("no end-of-block code") }
        return (try Huffman(lengths: Array(lengths[0..<nlen])), try Huffman(lengths: Array(lengths[nlen...])))
    }

    mutating func codes(_ lengths: Huffman, _ distances: Huffman) throws {
        while true {
            let sym = try decode(lengths)
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let li = sym - 257
            guard li < 29 else { throw PNGError("bad length symbol") }
            let len = Inflater.lengthBase[li] + (try bits(Inflater.lengthExtra[li]))
            let di = try decode(distances)
            guard di < 30 else { throw PNGError("bad distance symbol") }
            let dist = Inflater.distBase[di] + (try bits(Inflater.distExtra[di]))
            guard dist <= out.count else { throw PNGError("distance too far back") }
            let from = out.count - dist
            for k in 0..<len { out.append(out[from + k]) }   // may overlap what it's copying
        }
    }
}
