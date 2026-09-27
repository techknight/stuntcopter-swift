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
        try originalScreen(at: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Original/\(name)"), r)
    }

    func originalScreen(at url: URL, _ r: Rect) throws -> [[UInt8]] {
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

    /// Original/help.png, speed.png, source.png, offscreen.png: the original's Options
    /// dialogs as they first appear over the title screen (Set Speed with NORMAL chosen;
    /// OffScreen showing the attract loop's "117" height), each at its DLOG position.
    @Test(arguments: [("help.png", 3, 42, 60), ("speed.png", 4, 144, 72), ("source.png", 5, 110, 60),
                      ("offscreen.png", 6, 38, 46)])
    func optionsDialogMatchesTheOriginalPixelForPixel(file: String, item: Int, left: Int, top: Int) throws {
        let (game, _) = try makeGame()
        for _ in 0..<30 { game.tick() }                        // attract loop
        game.DoMenuCommand(StuntCopterGame.optionMenu, item)   // FakeHost answers item 1
        let dialog: ClassicDialog = switch item {
        case 3: game.HelpDialog
        case 4: game.SpeedDialog
        case 5: game.SourceDialog
        default: game.BitMapDialog
        }
        let bm = dialog.port.portBits
        let orig = try originalScreen(file, Rect(left: left, top: top, right: left + bm.width, bottom: top + bm.height))
        var diffs = 0
        for y in 0..<bm.height {
            for x in 0..<bm.width where bm.pixel(x, y) != orig[y][x] { diffs += 1 }
        }
        #expect(diffs == 0, "\(file): \(diffs) pixels differ")
    }

    /// For checking gameplay against the original: GAMEPLAY_PNG=<Snow screenshot taken
    /// after clicking BEGIN and leaving the mouse still> swift test --filter searchGameplayMatch
    /// Tries every mouse position inside BEGIN (the stick position for the whole game) and
    /// the loop counts around the wagon's position, and reports the best frame match.
    /// GAMEPLAY_FRAME="h,v,loops" GAMEPLAY_OUT=frame.pbm: render one candidate frame.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GAMEPLAY_FRAME"] != nil))
    func renderGameplayFrame() throws {
        let env = ProcessInfo.processInfo.environment
        let n = env["GAMEPLAY_FRAME"]!.split(separator: ",").map { Int($0)! }
        let (game, host) = try makeGame()
        host.mouse = Point(h: n[0], v: n[1])
        let click = Point(h: 250, v: 178)   // inside BEGIN; the stick uses host.mouse
        game.post(.mouseDown(click))
        game.post(.mouseUp(click))
        game.tick()
        for _ in 1..<n[2] { game.tick() }
        try pbmData(game.myWindow.portBits).write(to: URL(fileURLWithPath: env["GAMEPLAY_OUT"]!))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GAMEPLAY_PNG"] != nil))
    func searchGameplayMatch() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GAMEPLAY_PNG"]!)
        let orig = try originalScreen(at: url, Rect(left: 4, top: 30, right: 507, bottom: 340))
        func diffs(_ bm: BitMap, _ r: Rect) -> Int {
            var n = 0
            for y in r.top..<r.bottom { for x in r.left..<r.right where bm.pixel(x, y) != orig[y][x] { n += 1 } }
            return n
        }

        // Pass 1: the yoke cross depends only on the mouse (clamped to MouseRect), and each
        // cross drawing covers the yoke completely, so one game can try every position.
        let (game, host) = try makeGame()
        game.post(.mouseDown(Point(h: 250, v: 178)))
        game.post(.mouseUp(Point(h: 250, v: 178)))
        game.tick()
        let yoke = game.YokeErase
        var yokeMatches: [Point] = []
        for v in 134...206 {
            for h in 210...302 {
                host.mouse = Point(h: h, v: v)
                for _ in 0..<3 { game.tick() }
                if diffs(game.myWindow.portBits, yoke) == 0 { yokeMatches.append(host.mouse) }
            }
        }

        // Loops since BEGIN: the wagon starts at x = 0, moves 1 px per loop at WALK, and
        // wraps from 513 back to -69, a 582-loop cycle.
        var wagonLeft = Int.max
        for y in 232..<252 {
            if let x = (0..<503).first(where: { orig[y][$0] == 1 }) { wagonLeft = min(wagonLeft, x) }
        }
        // Pass 2: full frames for each distinct stick among the yoke matches.
        var best = (diffs: Int.max, h: 0, v: 0, loops: 0)
        var tried = Set<[Int]>()
        for p in yokeMatches {
            let key = [(p.h - 210) * 8 / 92, (p.v - 134) * 7 / 72]
            guard tried.insert(key).inserted else { continue }
            let (g, hst) = try makeGame()
            hst.mouse = p
            g.post(.mouseDown(Point(h: 250, v: 178)))
            g.post(.mouseUp(Point(h: 250, v: 178)))
            g.tick()
            var loops = 1
            for cycle in 0..<4 {
                let target = wagonLeft + 582 * cycle
                while loops < target - 3 { g.tick(); loops += 1 }
                for _ in 0..<7 {
                    let d = diffs(g.myWindow.portBits, Rect(left: 0, top: 0, right: 503, bottom: 310))
                    if d < best.diffs { best = (d, p.h, p.v, loops) }
                    g.tick(); loops += 1
                }
            }
        }
        print("GAMEPLAY wagon at \(wagonLeft); \(yokeMatches.count) mouse positions match the yoke " +
              "(\(tried.count) distinct sticks); best: \(best.diffs) differing pixels at (\(best.h), \(best.v)) after \(best.loops) loops")
    }
}
