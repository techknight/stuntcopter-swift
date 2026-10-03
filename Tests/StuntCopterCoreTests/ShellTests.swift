import ClassicToolbox
@testable import StuntCopterCore
import Testing

/// The platform-neutral parts of the shells (shared by the macOS and Windows apps).
@Suite struct ShellTests {
    // 32 loops/s and frame times in eighths keep the arithmetic exact in binary.
    @Test func pacerRunsLoopsPerSecondTimesRateFactor() {
        var pacer = FramePacer(loopsPerSecond: 32)
        #expect(pacer.steps(at: 1.0, rateFactor: 1) == 0)   // first frame: no reference time yet
        #expect(pacer.steps(at: 1.125, rateFactor: 1) == 4)
        #expect(pacer.steps(at: 1.25, rateFactor: 0.5) == 2)
        // Fractions carry over: 1/64 s at 32 loops/s is half a loop.
        var steps: [Int] = []
        for i in 1...6 { steps.append(pacer.steps(at: 1.25 + Double(i) / 64, rateFactor: 1)) }
        #expect(steps == [0, 1, 0, 1, 0, 1])
    }

    @Test func pacerDropsBacklogAfterAStall() {
        var pacer = FramePacer(loopsPerSecond: 32)
        _ = pacer.steps(at: 0.5, rateFactor: 1)
        #expect(pacer.steps(at: 10, rateFactor: 1) == 8)   // 0.25 s cap × 32 = the 8-loop cap
        #expect(pacer.steps(at: 10.125, rateFactor: 1) == 4)   // and nothing was banked
        pacer.reset()
        #expect(pacer.steps(at: 11, rateFactor: 1) == 0)   // after a modal dialog: no catch-up
        #expect(pacer.steps(at: 11.125, rateFactor: 1) == 4)
    }

    @Test func pacerDefaultsAnUnsetOverride() {
        #expect(FramePacer(loopsPerSecond: 0).loopsPerSecond == FramePacer.defaultLoopsPerSecond)
        #expect(FramePacer(loopsPerSecond: 45).loopsPerSecond == 45)
    }

    @Test func virtualPointerScalesDeltasAndStaysOnTheMacPlusScreen() {
        let origin = Point(h: 4, v: 30)   // StuntCopter's window in 1987
        var p = VirtualPointer(at: Point(h: 100, v: 100))
        p.move(dx: 7, dy: -5, scale: 2, windowOrigin: origin)
        #expect(p.point == Point(h: 103, v: 97))   // 3.5 rounds down
        p.move(dx: -10_000, dy: -10_000, scale: 1, windowOrigin: origin)
        #expect(p.point == Point(h: -4, v: -30))
        p.move(dx: 10_000, dy: 10_000, scale: 3, windowOrigin: origin)
        #expect(p.point == Point(h: 512 - 4, v: 342 - 30))
    }

    @Test func hostKeysBecomeThe1987Characters() {
        #expect(HostKey.backspace.character == "\u{8}")
        #expect(HostKey.escape.character == "\u{1B}")
        #expect(HostKey.enter.character == "\u{3}")
        #expect(HostKey.character("\r").character == "\r")
    }

    @Test func windowScaleFitsTheScreen() {
        let w = Rect(top: 0, left: 0, bottom: 310, right: 503)
        #expect(WindowScale.fitting(w, width: 1512, height: 900) == 2)
        #expect(WindowScale.fitting(w, width: 5000, height: 5000) == 4)
        #expect(WindowScale.fitting(w, width: 5000, height: 5000, limit: nil) == 9)
        #expect(WindowScale.fitting(w, width: 100, height: 100) == 1)
        #expect(WindowScale.initial(w, screenWidth: nil, screenHeight: nil) == 2)
    }

    @MainActor
    @Test func dialogFrameWrapsTheContentInTheDBoxProcBorder() throws {
        let (game, _) = try makeGame()
        let frame = DialogFrame(dialog: game.AboutDialog)
        let f = DialogFrame.width
        let c = frame.composite
        #expect(c.width == game.AboutDialog.size.width + 2 * f)
        #expect(c.height == game.AboutDialog.size.height + 2 * f)
        // Outside in: 1 black, 2 white, 2 black, 3 white, on every edge.
        for d in 0..<f {
            #expect(c.pixel(d, c.height / 2) == DialogFrame.pattern[d])
            #expect(c.pixel(c.width - 1 - d, c.height / 2) == DialogFrame.pattern[d])
            #expect(c.pixel(c.width / 2, d) == DialogFrame.pattern[d])
            #expect(c.pixel(c.width / 2, c.height - 1 - d) == DialogFrame.pattern[d])
        }
        game.AboutDialog.port.portBits.setPixel(0, 0, 1)
        let before = c.generation
        frame.refresh()
        #expect(c.generation != before)
        #expect(c.pixel(f, f) == 1)
        #expect(frame.contentPoint(Point(h: f + 3, v: f + 4)) == Point(h: 3, v: 4))
        let b = game.AboutDialog.template.boundsRect
        #expect(frame.origin(relativeToWindowAt: Point(h: 4, v: 30)) == Point(h: b.left - 4 - f, v: b.top - 30 - f))
    }

    @Test func grayscaleBytesAreBlackOnWhite() {
        let bm = BitMap(bounds: Rect(top: 0, left: 0, bottom: 2, right: 3))
        bm.setPixel(1, 0, 1)
        bm.setPixel(2, 1, 1)
        #expect(bm.grayscaleBytes() == [255, 0, 255, 255, 255, 0])
    }
}
