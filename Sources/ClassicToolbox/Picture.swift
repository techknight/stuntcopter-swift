import Foundation


/// A decoded QuickDraw picture. Only what StuntCopter's PICTs contain is supported:
/// version 1 pictures made of (PackBits)BitsRect opcodes (Inside Macintosh I-158,
/// Tech Note 21). Each bitmap op is kept with its destination rect in picture space.
public struct Picture {
    public struct BitsOp {
        public let bitmap: BitMap
        public let srcRect: Rect
        public let dstRect: Rect
        public let mode: Int
    }

    public let picFrame: Rect
    public let ops: [BitsOp]

    public init(pictData d: [UInt8]) throws {
        let r = ByteReader(d)
        guard d.count >= 12 else { throw ResourceError.malformed("PICT header") }
        picFrame = r.rect(2)
        var ops: [BitsOp] = []
        var p = 10
        loop: while p < d.count {
            let op = r.u8(p); p += 1
            switch op {
            case 0x00: continue                          // NOP
            case 0x11: p += 1                            // picVersion
            case 0x01: p += r.u16(p)                     // clipRgn (size includes itself)
            case 0xA0: p += 2                            // ShortComment
            case 0xA1: p += 4 + r.u16(p + 2)             // LongComment
            case 0x90, 0x98:                             // BitsRect / PackBitsRect
                let rowBytes = r.u16(p) & 0x7FFF
                let bounds = r.rect(p + 2)
                let srcRect = r.rect(p + 10)
                let dstRect = r.rect(p + 18)
                let mode = r.i16(p + 26)
                p += 28
                let height = bounds.height
                var packed = [UInt8]()
                packed.reserveCapacity(rowBytes * height)
                if op == 0x90 || rowBytes < 8 {
                    packed.append(contentsOf: d[p..<(p + rowBytes * height)])
                    p += rowBytes * height
                } else {
                    for _ in 0..<height {
                        let count: Int
                        if rowBytes > 250 { count = r.u16(p); p += 2 } else { count = r.u8(p); p += 1 }
                        let row = unpackBits(Array(d[p..<(p + count)]), expected: rowBytes)
                        guard row.count == rowBytes else { throw ResourceError.malformed("PackBits row length") }
                        packed.append(contentsOf: row)
                        p += count
                    }
                }
                ops.append(BitsOp(bitmap: BitMap(bounds: bounds, packed: packed, rowBytes: rowBytes),
                                  srcRect: srcRect, dstRect: dstRect, mode: mode))
            case 0xFF:
                break loop
            default:
                throw ResourceError.malformed(String(format: "unsupported PICT opcode $%02X", op))
            }
        }
        self.ops = ops
    }
}

/// Apple PackBits run-length decoding.
public func unpackBits(_ src: [UInt8], expected: Int) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(expected)
    var i = 0
    while i < src.count {
        let n = Int(Int8(bitPattern: src[i])); i += 1
        if n >= 0 {
            let end = min(i + n + 1, src.count)
            out.append(contentsOf: src[i..<end])
            i = end
        } else if n != -128 {
            guard i < src.count else { break }
            out.append(contentsOf: repeatElement(src[i], count: 1 - n))
            i += 1
        }
    }
    return out
}
