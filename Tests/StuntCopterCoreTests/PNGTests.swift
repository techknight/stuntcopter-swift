import Foundation
import Testing
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// The test suite's own PNG codec (PNG.swift) has to be right for the comparisons with the
/// original to mean anything, so check it: portably against known values, and on macOS
/// against ImageIO.
@Suite struct PNGTests {
    @Test func checksumsMatchKnownValues() {
        #expect(PNG.crc32(Array("123456789".utf8)[...]) == 0xCBF4_3926)
        #expect(PNG.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
        #expect(PNG.adler32([UInt8](repeating: 0xFF, count: 100_000)) == 0x149A_302C)
    }

    /// zlib.compress(b"StuntCopter StuntCopter StuntCopter, 1987", 9): one fixed-Huffman
    /// block with back-references.
    @Test func inflatesAFixedHuffmanBlock() throws {
        let z: [UInt8] = [0x78, 0xDA, 0x0B, 0x2E, 0x29, 0xCD, 0x2B, 0x71, 0xCE, 0x2F, 0x28, 0x49, 0x2D, 0x52, 0x08,
                          0xC6, 0xCE, 0xD6, 0x51, 0x30, 0xB4, 0xB4, 0x30, 0x07, 0x00, 0x4F, 0xFD, 0x0F, 0x07]
        #expect(try zlibDecompress(z) == Array("StuntCopter StuntCopter StuntCopter, 1987".utf8))
    }

    @Test func rejectsACorruptStream() {
        var z: [UInt8] = [0x78, 0xDA, 0x0B, 0x2E, 0x29, 0xCD, 0x2B, 0x71, 0xCE, 0x2F, 0x28, 0x49, 0x2D, 0x52, 0x08,
                          0xC6, 0xCE, 0xD6, 0x51, 0x30, 0xB4, 0xB4, 0x30, 0x07, 0x00, 0x4F, 0xFD, 0x0F, 0x07]
        z[z.count - 1] ^= 1
        #expect(throws: PNGError.self) { try zlibDecompress(z) }
    }

    /// Larger than one stored block (65,535 bytes), so the encoder has to split it.
    @Test func grayRoundTrips() throws {
        let w = 300, h = 250
        let gray = (0..<w * h).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) }
        let img = try PNG.decode([UInt8](PNG.encodeGray(width: w, height: h, gray: gray)))
        #expect(img.width == w && img.height == h)
        #expect(img.gray == gray)
    }

    @Test func originalScreenshotsAreTwoToneAndOpaque() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Original")
        for name in ["about", "attract-440", "help", "offscreen", "source", "speed"] {
            let img = try PNG.decode(contentsOf: dir.appendingPathComponent("\(name).png"))
            #expect(img.width == 512 && img.height == 342)
            #expect(Set(img.gray) == [0x22, 0xEE], "\(name).png")
        }
    }

    #if canImport(ImageIO)
    static let originals = ["about", "attract-440", "help", "offscreen", "source", "speed"]

    /// The Snow screenshots decode to exactly what ImageIO gives.
    @Test(arguments: originals) func decodesLikeImageIO(_ name: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Original/\(name).png")
        #expect(try PNG.decode(contentsOf: url).rgba == imageIORGBA(try Data(contentsOf: url)))
    }

    /// ImageIO can open what the encoder writes.
    @Test func imageIOReadsTheEncodersOutput() throws {
        let w = 97, h = 700
        let gray = (0..<w * h).map { UInt8(truncatingIfNeeded: $0 &* 40_503 >> 7) }
        let rgba = try imageIORGBA(PNG.encodeGray(width: w, height: h, gray: gray))
        #expect((0..<w * h).allSatisfy { rgba[4 * $0] == gray[$0] && rgba[4 * $0 + 3] == 255 })
    }

    enum Layout: String, CaseIterable, Sendable { case gray1, gray8, rgb8, rgba8, rgb16, palette8 }

    /// Noise written by ImageIO (libpng picks per-row filters adaptively, so all five turn
    /// up) in a range of colour types and depths, decoded by PNG.swift.
    @Test(arguments: Layout.allCases) func decodesImageIOEncodings(_ layout: Layout) throws {
        let w = 61, h = 23   // odd width: partial bytes at 1 bit, unaligned rows
        var seed: UInt32 = 0x5EED
        func noise() -> UInt8 { seed = seed &* 1_664_525 &+ 1_013_904_223; return UInt8(seed >> 24) }
        let samples: Int, bitsPerComponent: Int, space: CGColorSpace, info: UInt32
        switch layout {
        case .gray1: (samples, bitsPerComponent, space, info) = (1, 1, CGColorSpaceCreateDeviceGray(), 0)
        case .gray8: (samples, bitsPerComponent, space, info) = (1, 8, CGColorSpaceCreateDeviceGray(), 0)
        case .rgb8: (samples, bitsPerComponent, space, info) = (3, 8, CGColorSpaceCreateDeviceRGB(), 0)
        case .rgba8:
            (samples, bitsPerComponent, space, info) =
                (4, 8, CGColorSpaceCreateDeviceRGB(), CGImageAlphaInfo.last.rawValue)
        case .rgb16:
            (samples, bitsPerComponent, space, info) =
                (3, 16, CGColorSpaceCreateDeviceRGB(), CGBitmapInfo.byteOrder16Big.rawValue)
        case .palette8:
            let table = (0..<256 * 3).map { _ in noise() }
            (samples, bitsPerComponent, space, info) =
                (1, 8, CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: table)!, 0)
        }
        let bytesPerRow = (w * samples * bitsPerComponent + 7) / 8
        var raw = (0..<bytesPerRow * h).map { _ in noise() }
        if layout == .rgba8 { for i in stride(from: 3, to: raw.count, by: 4) { raw[i] = 255 } }   // no premultiply drift
        let image = try #require(CGImage(
            width: w, height: h, bitsPerComponent: bitsPerComponent, bitsPerPixel: samples * bitsPerComponent,
            bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: CGDataProvider(data: Data(raw) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let png = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))

        let ours = try PNG.decode([UInt8](png as Data))
        #expect(ours.width == w && ours.height == h)
        #expect(ours.rgba == (try imageIORGBA(png as Data)), "\(layout)")
    }

    /// ImageIO's decode as unpremultiplied 8-bit RGBA in the image's own colour space (no
    /// colour matching), which is what PNG.swift produces.
    func imageIORGBA(_ data: Data) throws -> [UInt8] {
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let provider = try #require(img.dataProvider?.data as Data?)
        let bytes = [UInt8](provider)
        let w = img.width, bpc = img.bitsPerComponent, bpp = img.bitsPerPixel
        let components = bpp / bpc
        let littleEndian16 = img.bitmapInfo.contains(.byteOrder16Little)   // how ImageIO hands back 16-bit PNGs
        var out = [UInt8](repeating: 255, count: w * img.height * 4)
        for y in 0..<img.height {
            for x in 0..<w {
                func c(_ k: Int) -> Int {
                    switch bpc {
                    case 16: let o = y * img.bytesPerRow + (x * components + k) * 2
                        let (hi, lo) = littleEndian16 ? (bytes[o + 1], bytes[o]) : (bytes[o], bytes[o + 1])
                        return (Int(hi) << 8 | Int(lo)) * 255 / 65_535
                    case 8: return Int(bytes[y * img.bytesPerRow + x * components + k])
                    default:
                        let bit = (x * components + k) * bpc
                        let v = Int(bytes[y * img.bytesPerRow + bit / 8] >> (8 - bpc - bit % 8)) & (1 << bpc - 1)
                        return v * 255 / (1 << bpc - 1)
                    }
                }
                let o = 4 * (y * w + x)
                if let cs = img.colorSpace, cs.model == .indexed, let table = cs.colorTable {
                    let p = c(0)
                    for k in 0..<3 { out[o + k] = table[3 * p + k] }
                } else if components >= 3 {
                    for k in 0..<3 { out[o + k] = UInt8(c(k)) }
                    if components == 4 { out[o + 3] = UInt8(c(3)) }
                } else {
                    for k in 0..<3 { out[o + k] = UInt8(c(0)) }
                    if components == 2 { out[o + 3] = UInt8(c(1)) }
                }
            }
        }
        #expect(![.premultipliedFirst, .premultipliedLast, .first, .noneSkipFirst].contains(img.alphaInfo),
                "unexpected ImageIO layout \(img.alphaInfo.rawValue)")
        return out
    }
    #endif
}
