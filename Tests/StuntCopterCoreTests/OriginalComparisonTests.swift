import ClassicToolbox
import CoreGraphics
import Foundation
import ImageIO
@testable import StuntCopterCore
import Testing

/// Compares the port with the real thing: Original/attract-440.png is a screenshot of
/// StuntCopter 1.5 running on an emulated Mac Plus (Snow, System 6.0.8), taken 440
/// attract-mode loops after launch, mid-loop: the copter had been drawn for loop 440
/// but the wagon not yet moved. Nothing in attract mode is random, so the port must
/// reproduce it exactly.
@MainActor
@Suite struct OriginalComparisonTests {
    /// The 512×342 screen as 0/1 pixels, cropped to the game window at (4, 30).
    func originalWindow() throws -> [[UInt8]] {
        try originalScreen("attract-440.png", Rect(left: 4, top: 30, right: 507, bottom: 340))
    }

    /// Part of an emulator screenshot (512×342) as 0/1 pixels.
    func originalScreen(_ name: String, _ r: Rect) throws -> [[UInt8]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Original/\(name)")
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var gray = [UInt8](repeating: 0, count: img.width * img.height)
        let ctx = try #require(CGContext(data: &gray, width: img.width, height: img.height, bitsPerComponent: 8,
                                         bytesPerRow: img.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return (r.top..<r.bottom).map { y in (r.left..<r.right).map { x in gray[y * img.width + x] < 128 ? 1 : 0 } }
    }

    func frame(afterLoops n: Int) throws -> BitMap {
        let (game, _) = try makeGame()
        for _ in 0..<n { game.tick() }
        return game.myWindow.portBits
    }

    func differences(_ bm: BitMap, _ orig: [[UInt8]], rows: Range<Int>) -> Int {
        rows.reduce(0) { sum, y in sum + (0..<503).filter { bm.pixel($0, y) != orig[y][$0] }.count }
    }

    @Test func attractFrameMatchesTheOriginalPixelForPixel() throws {
        let orig = try originalWindow()
        let copterRows = 100..<140
        // Everything except the copter matches after 439 complete loops…
        let f439 = try frame(afterLoops: 439)
        #expect(differences(f439, orig, rows: 0..<copterRows.lowerBound) == 0)
        #expect(differences(f439, orig, rows: copterRows.upperBound..<310) == 0)
        // …and the copter matches the one drawn at the start of loop 440.
        let f440 = try frame(afterLoops: 440)
        #expect(differences(f440, orig, rows: copterRows) == 0)
    }

    /// Original/about.png: the original's About box (DLOG 130 at global 38,34, 436×292),
    /// as ModalDialog first shows it: items drawn over the cloud and BackFlip frame.
    @Test func aboutBoxMatchesTheOriginalPixelForPixel() throws {
        let orig = try originalScreen("about.png", Rect(left: 38, top: 34, right: 474, bottom: 326))
        let (game, host) = try makeGame()
        host.modalAnswers = [3]
        game.DoMenuCommand(StuntCopterGame.appleMenu, 1)
        let bm = game.AboutDialog.port.portBits
        let diffs = (0..<292).reduce(0) { sum, y in sum + (0..<436).filter { bm.pixel($0, y) != orig[y][$0] }.count }
        #expect(diffs == 0)
    }
}
