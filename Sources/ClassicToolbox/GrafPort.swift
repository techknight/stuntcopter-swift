/// An 8×8 1-bit QuickDraw pattern.
public struct Pattern: Equatable, Sendable {
    public let rows: [UInt8]

    public init(_ rows: [UInt8]) {
        precondition(rows.count == 8)
        self.rows = rows
    }

    @inline(__always)
    public func bit(_ x: Int, _ y: Int) -> UInt8 {
        (rows[y & 7] >> (7 - UInt8(x & 7))) & 1
    }

    public static let white = Pattern([0, 0, 0, 0, 0, 0, 0, 0])
    public static let black = Pattern([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    public static let gray = Pattern([0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55])
    public static let ltGray = Pattern([0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22])
    public static let dkGray = Pattern([0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD])
}

public let white = Pattern.white
public let black = Pattern.black
public let gray = Pattern.gray
public let ltGray = Pattern.ltGray
public let dkGray = Pattern.dkGray

/// Source transfer modes (I-157).
public enum TransferMode: Sendable { case srcCopy, srcOr, srcXor, srcBic }
public let srcCopy = TransferMode.srcCopy
public let srcOr = TransferMode.srcOr
public let srcXor = TransferMode.srcXor
public let srcBic = TransferMode.srcBic

public struct TextStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let bold = TextStyle(rawValue: 1)
    public static let underline = TextStyle(rawValue: 4)
}
public let bold = TextStyle.bold
public let underline = TextStyle.underline

/// A drawing environment (I-147). Window ports use local coordinates with (0,0)
/// at the top-left of the content area.
public final class GrafPort {
    public var portBits: BitMap
    public var portRect: Rect
    /// nil means "wide open" (QuickDraw's default huge rectangle).
    public var clipRgn: Region?
    public var visRgn: Region?
    public var pnLoc = Point.zero
    public var txFace: TextStyle = []
    public var txMode: TransferMode = .srcOr
    public var bkPat: Pattern = .white
    /// Window ports only: the area InvalRect has marked for the next update event.
    public let updateRgn = Region()

    public init(bitmap: BitMap) {
        portBits = bitmap
        portRect = bitmap.bounds
        visRgn = Region(rect: bitmap.bounds)
    }

    public convenience init(size: Rect) {
        self.init(bitmap: BitMap(bounds: size))
    }
}
