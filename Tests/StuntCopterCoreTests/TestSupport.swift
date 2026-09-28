import ClassicToolbox
import Foundation
@testable import StuntCopterCore

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
    try? PNG.encodeGray(width: w, height: h, gray: gray).write(to: url)
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

/// Mono 32-bit float WAV, the format AVAudioFile wrote for these samples.
func wavData(_ samples: [Float], sampleRate: Int) -> Data {
    func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }
    func le16(_ v: Int) -> [UInt8] { (0..<2).map { UInt8(v >> (8 * $0) & 0xFF) } }
    let dataBytes = samples.count * 4
    var d = Array("RIFF".utf8) + le32(36 + dataBytes) + Array("WAVEfmt ".utf8) + le32(16)
    d += le16(3) + le16(1) + le32(sampleRate) + le32(sampleRate * 4) + le16(4) + le16(32)   // IEEE float
    d += Array("data".utf8) + le32(dataBytes)
    for s in samples { d += le32(Int(s.bitPattern)) }
    return Data(d)
}
