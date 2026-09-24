import ClassicToolbox
import CoreGraphics
import Foundation
import ImageIO
@testable import StuntCopterCore
import UniformTypeIdentifiers

/// A scriptable stand-in for the AppKit shell.
@MainActor
final class FakeHost: GameHost {
    var mouse = Point(h: 256, v: 170)
    var cursorHidden = false
    var messageMenuShown = false
    var menusEnabled = true
    var soundChecked = false
    var hiScore = 0
    var dialogsShown: [Int] = []
    /// Items ModalDialog returns, in order (defaults to 1).
    var modalAnswers: [Int] = []
    var ticks = 0

    func getMouse() -> Point { mouse }
    func hideCursor() { cursorHidden = true }
    func showCursor() { cursorHidden = false }
    func drawMenuBar(messageMenuShown: Bool, menusEnabled: Bool) {
        self.messageMenuShown = messageMenuShown
        self.menusEnabled = menusEnabled
    }
    func checkSoundItem(_ on: Bool) { soundChecked = on }
    func showDialogWindow(_ d: ClassicDialog) { dialogsShown.append(d.id) }
    func hideDialogWindow(_ d: ClassicDialog) {}
    func modalDialog(_ d: ClassicDialog) -> Int { modalAnswers.isEmpty ? 1 : modalAnswers.removeFirst() }
    func pause(ticks: Int) { self.ticks += ticks }
    func savedHiScore() -> Int { hiScore }
    func hiScoreChanged(_ hiScore: Int) { self.hiScore = hiScore }
    func quit() {}
}

@MainActor
func makeGame(host: FakeHost = FakeHost()) throws -> (StuntCopterGame, FakeHost) {
    let game = try StuntCopterGame(host: host)
    game.tickSource = { host.ticks }   // also keeps the (weakly held) host alive
    try game.start()
    game.tick()   // first update event
    return (game, host)
}

// MARK: - Golden images (PBM P4, the simplest 1-bit format)

func pbmData(_ bm: BitMap) -> Data {
    var d = Data("P4\n\(bm.width) \(bm.height)\n".utf8)
    let rowBytes = (bm.width + 7) / 8
    for y in 0..<bm.height {
        var row = [UInt8](repeating: 0, count: rowBytes)
        for x in 0..<bm.width where bm.pixels[y * bm.width + x] != 0 {
            row[x / 8] |= UInt8(0x80 >> (x % 8))
        }
        d.append(contentsOf: row)
    }
    return d
}

func writePNG(_ bm: BitMap, to url: URL, scale: Int = 2) {
    let w = bm.width * scale, h = bm.height * scale
    var gray = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w where bm.pixels[(y / scale) * bm.width + x / scale] == 0 { gray[y * w + x] = 255 }
    }
    let provider = CGDataProvider(data: Data(gray) as CFData)!
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let goldenDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden")

/// Compares a bitmap with Golden/<name>.pbm. Set RECORD_GOLDEN=1 to (re)write it;
/// set SNAPSHOT_PNG_DIR to also get a viewable PNG.
func matchesGolden(_ bm: BitMap, _ name: String) -> Bool {
    let data = pbmData(bm)
    let env = ProcessInfo.processInfo.environment
    if let dir = env["SNAPSHOT_PNG_DIR"] {
        writePNG(bm, to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    let url = goldenDir.appendingPathComponent("\(name).pbm")
    if env["RECORD_GOLDEN"] == "1" {
        try? FileManager.default.createDirectory(at: goldenDir, withIntermediateDirectories: true)
        try? data.write(to: url)
        return true
    }
    guard let golden = try? Data(contentsOf: url) else { return false }
    return golden == data
}
