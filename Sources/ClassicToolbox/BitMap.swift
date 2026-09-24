/// A 1-bit QuickDraw BitMap. Pixels are stored one per byte (0 = white, 1 = black)
/// for simplicity; `rowBytes` is kept only for fidelity/diagnostics.
public final class BitMap {
    public let bounds: Rect
    public var pixels: [UInt8]
    /// Bumped on every mutation so hosts can cheaply tell if a redraw is needed.
    public private(set) var generation: Int = 0

    public init(bounds: Rect) {
        self.bounds = bounds
        self.pixels = [UInt8](repeating: 0, count: max(0, bounds.width * bounds.height))
    }

    public var width: Int { bounds.width }
    public var height: Int { bounds.height }

    /// Classic rowBytes for a 1-bit bitmap of this width (always even).
    public var rowBytes: Int { ((width - 1) / 16 + 1) * 2 }

    @inline(__always)
    public func index(_ x: Int, _ y: Int) -> Int {
        (y - bounds.top) * width + (x - bounds.left)
    }

    @inline(__always)
    public func pixel(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= bounds.left, x < bounds.right, y >= bounds.top, y < bounds.bottom else { return 0 }
        return pixels[index(x, y)]
    }

    @inline(__always)
    public func setPixel(_ x: Int, _ y: Int, _ value: UInt8) {
        guard x >= bounds.left, x < bounds.right, y >= bounds.top, y < bounds.bottom else { return }
        pixels[index(x, y)] = value
    }

    public func markChanged() { generation &+= 1 }

    /// Pixels as packed rows of `rowBytes` bytes (MSB first), the classic memory layout.
    public func packedRows() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] != 0 {
                out[y * rowBytes + x / 8] |= UInt8(0x80 >> (x % 8))
            }
        }
        return out
    }

    /// Builds a bitmap from packed 1-bit rows.
    public convenience init(bounds: Rect, packed: [UInt8], rowBytes: Int) {
        self.init(bounds: bounds)
        let w = bounds.width
        for y in 0..<bounds.height {
            for x in 0..<w {
                let byte = packed[y * rowBytes + x / 8]
                pixels[y * w + x] = (byte >> (7 - UInt8(x % 8))) & 1
            }
        }
    }
}
