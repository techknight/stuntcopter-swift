import Foundation

public enum ResourceError: Error, CustomStringConvertible {
    case malformed(String)
    case notFound(String, Int)

    public var description: String {
        switch self {
        case .malformed(let s): return "malformed resource data: \(s)"
        case .notFound(let t, let id): return "resource '\(t)' \(id) not found"
        }
    }
}

/// Big-endian reader over a byte array.
struct ByteReader {
    let d: [UInt8]
    init(_ d: [UInt8]) { self.d = d }
    func u8(_ p: Int) -> Int { Int(d[p]) }
    func u16(_ p: Int) -> Int { Int(d[p]) << 8 | Int(d[p + 1]) }
    func i16(_ p: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(p)))) }
    func u24(_ p: Int) -> Int { Int(d[p]) << 16 | Int(d[p + 1]) << 8 | Int(d[p + 2]) }
    func u32(_ p: Int) -> Int { u16(p) << 16 | u16(p + 2) }
    func i32(_ p: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(p)))) }
    func rect(_ p: Int) -> Rect { Rect(top: i16(p), left: i16(p + 2), bottom: i16(p + 4), right: i16(p + 6)) }
    func pstring(_ p: Int) -> String { macRoman(Array(d[(p + 1)..<(p + 1 + u8(p))])) }
}

/// Decodes Mac OS Roman text, mapping CR to "\r".
public func macRoman(_ bytes: [UInt8]) -> String {
    String(bytes: bytes, encoding: .macOSRoman) ?? String(decoding: bytes, as: UTF8.self)
}

public struct ResourceEntry: Sendable {
    public let type: String
    public let id: Int
    public let name: String?
    public let attributes: Int
    public let data: [UInt8]
}

/// A parsed classic Mac resource fork (Inside Macintosh I-128).
public final class ResourceFork: Sendable {
    public let entries: [ResourceEntry]

    public init(forkData d: [UInt8]) throws {
        guard d.count >= 16 else { throw ResourceError.malformed("fork header") }
        let r = ByteReader(d)
        let dataOff = r.u32(0), mapOff = r.u32(4), mapLen = r.u32(12)
        guard mapOff + mapLen <= d.count else { throw ResourceError.malformed("map out of range") }
        let typeListOff = mapOff + r.u16(mapOff + 24)
        let nameListOff = mapOff + r.u16(mapOff + 26)
        let typeCount = r.u16(typeListOff) &+ 1
        var entries: [ResourceEntry] = []
        for t in 0..<(typeCount & 0xFFFF) {
            let te = typeListOff + 2 + 8 * t
            let type = macRoman(Array(d[te..<(te + 4)]))
            let count = r.u16(te + 4) + 1
            let refListOff = typeListOff + r.u16(te + 6)
            for k in 0..<count {
                let re = refListOff + 12 * k
                let id = r.i16(re)
                let nameOff = r.u16(re + 2)
                let attrs = r.u8(re + 4)
                let off = dataOff + r.u24(re + 5)
                let len = r.u32(off)
                guard off + 4 + len <= d.count else { throw ResourceError.malformed("\(type) \(id) data") }
                let name = nameOff == 0xFFFF ? nil : r.pstring(nameListOff + nameOff)
                entries.append(ResourceEntry(type: type, id: id, name: name, attributes: attrs,
                                             data: Array(d[(off + 4)..<(off + 4 + len)])))
            }
        }
        self.entries = entries
    }

    /// Extracts the resource fork (entry id 2) from an AppleDouble ("._name") file.
    public static func resourceForkData(fromAppleDouble d: [UInt8]) throws -> [UInt8] {
        let r = ByteReader(d)
        guard d.count >= 26, r.u32(0) == 0x0005_1607 else { throw ResourceError.malformed("not AppleDouble") }
        let n = r.u16(24)
        for i in 0..<n {
            let e = 26 + 12 * i
            if r.u32(e) == 2 {
                let off = r.u32(e + 4), len = r.u32(e + 8)
                return Array(d[off..<(off + len)])
            }
        }
        throw ResourceError.malformed("AppleDouble has no resource fork")
    }

    public func get(_ type: String, _ id: Int) throws -> [UInt8] {
        guard let e = entries.first(where: { $0.type == type && $0.id == id }) else {
            throw ResourceError.notFound(type, id)
        }
        return e.data
    }

    public func has(_ type: String, _ id: Int) -> Bool {
        entries.contains { $0.type == type && $0.id == id }
    }

    // MARK: Typed accessors

    public func picture(_ id: Int) throws -> Picture { try Picture(pictData: get("PICT", id)) }

    public func region(_ id: Int) throws -> Region { try Region(qdData: get("RGN ", id)) }

    /// GetIndString: 1-based index into a 'STR#'.
    public func indString(_ id: Int, _ index: Int) throws -> String {
        let d = try get("STR#", id)
        let r = ByteReader(d)
        let n = r.u16(0)
        var p = 2
        for i in 1...max(1, n) {
            if i == index { return r.pstring(p) }
            p += 1 + r.u8(p)
        }
        throw ResourceError.notFound("STR#[\(index)]", id)
    }

    public func window(_ id: Int) throws -> WindowTemplate {
        let d = try get("WIND", id)
        let r = ByteReader(d)
        return WindowTemplate(boundsRect: r.rect(0), procID: r.i16(8), visible: r.u16(10) != 0,
                              title: d.count > 18 ? r.pstring(18) : "")
    }

    public func dialog(_ id: Int) throws -> DialogTemplate {
        let d = try get("DLOG", id)
        let r = ByteReader(d)
        return DialogTemplate(boundsRect: r.rect(0), procID: r.i16(8), itemsID: r.i16(18),
                              title: d.count > 20 ? r.pstring(20) : "")
    }

    public func control(_ id: Int) throws -> ControlTemplate {
        let d = try get("CNTL", id)
        let r = ByteReader(d)
        return ControlTemplate(boundsRect: r.rect(0), value: r.i16(8), visible: r.u16(10) != 0,
                               max: r.i16(12), min: r.i16(14), procID: r.i16(16), title: r.pstring(22))
    }

    public func itemList(_ id: Int) throws -> [DialogItemTemplate] {
        let d = try get("DITL", id)
        let r = ByteReader(d)
        let n = r.i16(0) + 1
        var items: [DialogItemTemplate] = []
        var p = 2
        for _ in 0..<n {
            let rect = r.rect(p + 4)
            let type = r.u8(p + 12)
            let len = r.u8(p + 13)
            let payload = Array(d[(p + 14)..<(p + 14 + len)])
            items.append(DialogItemTemplate(rect: rect, rawType: type, payload: payload))
            p += 14 + len + (len & 1)
        }
        return items
    }

    public func menu(_ id: Int) throws -> MenuTemplate {
        let d = try get("MENU", id)
        let r = ByteReader(d)
        var p = 14
        let title = r.pstring(p)
        p += 1 + r.u8(p)
        var items: [MenuTemplate.Item] = []
        while p < d.count, r.u8(p) != 0 {
            let text = r.pstring(p)
            p += 1 + r.u8(p)
            items.append(.init(text: text, icon: r.u8(p), keyEquivalent: r.u8(p + 1),
                               mark: r.u8(p + 2), style: r.u8(p + 3)))
            p += 4
        }
        return MenuTemplate(id: r.i16(0), title: title, items: items)
    }

    /// 'ICON' (32×32, 1-bit) as a BitMap.
    public func icon(_ id: Int) throws -> BitMap {
        let d = try get("ICON", id)
        return BitMap(bounds: Rect(top: 0, left: 0, bottom: 32, right: 32), packed: d, rowBytes: 4)
    }

    /// 'ICN#': icon bitmap and its mask.
    public func iconList(_ id: Int) throws -> (icon: BitMap, mask: BitMap) {
        let d = try get("ICN#", id)
        let b = Rect(top: 0, left: 0, bottom: 32, right: 32)
        return (BitMap(bounds: b, packed: Array(d[0..<128]), rowBytes: 4),
                BitMap(bounds: b, packed: Array(d[128..<256]), rowBytes: 4))
    }
}

public struct WindowTemplate: Sendable {
    public let boundsRect: Rect
    public let procID: Int
    public let visible: Bool
    public let title: String
}

public struct DialogTemplate: Sendable {
    public let boundsRect: Rect
    public let procID: Int
    public let itemsID: Int
    public let title: String
}

public struct ControlTemplate: Sendable {
    public let boundsRect: Rect
    public let value: Int
    public let visible: Bool
    public let max: Int
    public let min: Int
    public let procID: Int
    public let title: String
}

public struct DialogItemTemplate: Sendable {
    public enum Kind: Sendable { case button, checkBox, radioButton, staticText, editText, icon, picture, userItem, other }

    public let rect: Rect
    public let rawType: Int
    public let payload: [UInt8]

    public var disabled: Bool { rawType & 0x80 != 0 }

    public var kind: Kind {
        switch rawType & 0x7F {
        case 4: return .button
        case 5: return .checkBox
        case 6: return .radioButton
        case 8: return .staticText
        case 16: return .editText
        case 32: return .icon
        case 64: return .picture
        case 0: return .userItem
        default: return .other
        }
    }

    public var text: String { macRoman(payload) }

    /// Resource ID for icon/picture items.
    public var resourceID: Int { payload.count >= 2 ? Int(Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1]))) : 0 }
}

public struct MenuTemplate: Sendable {
    public struct Item: Sendable {
        public let text: String
        public let icon: Int
        public let keyEquivalent: Int
        public let mark: Int
        public let style: Int
    }
    public let id: Int
    public let title: String
    public let items: [Item]
}
