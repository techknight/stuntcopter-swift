@testable import ClassicToolbox
import Foundation
@testable import StuntCopterCore
import Testing

let fork = try! ResourceFork(forkData: EmbeddedResources.stuntCopterFork)

@Suite struct ResourceTests {
    @Test func inventoryMatchesTheOriginalApplication() {
        let byType = Dictionary(grouping: fork.entries, by: \.type).mapValues { $0.map(\.id).sorted() }
        #expect(byType["PICT"] == [128, 129, 130, 356, 357, 358])
        #expect(byType["RGN "] == [356, 357, 358])
        #expect(byType["DLOG"] == [129, 130, 137, 138, 139])
        #expect(byType["DITL"] == [129, 130, 131, 140, 141])
        #expect(byType["CNTL"] == [129, 130, 131, 132])
        #expect(byType["MENU"] == [1, 256, 257, 258])
        #expect(byType["ICN#"] == [129])
        #expect(byType["ICON"] == [130])
    }

    @Test(arguments: [(128, 224, 143), (129, 120, 143), (130, 387, 51), (356, 119, 44), (357, 210, 45), (358, 140, 73)])
    func pictureFrames(id: Int, width: Int, height: Int) throws {
        let pic = try fork.picture(id)
        #expect(pic.picFrame.width == width)
        #expect(pic.picFrame.height == height)
        #expect(pic.ops.count == 1)
        let op = pic.ops[0]
        #expect(op.bitmap.pixels.count == op.bitmap.bounds.width * op.bitmap.bounds.height)
        #expect(op.dstRect == pic.picFrame)
    }

    @Test(arguments: [356, 357, 358])
    func cloudRegionsFitTheirPictures(id: Int) throws {
        let rgn = try fork.region(id)
        let frame = try fork.picture(id).picFrame
        #expect(!rgn.isEmpty)
        let bbox = rgn.rgnBBox
        #expect(bbox.width <= frame.width + 2 && bbox.height <= frame.height + 2, "\(bbox) vs \(frame)")
    }

    @Test func stringsWindowAndControls() throws {
        #expect(try fork.indString(256, 1) == "StuntCopter 1.5 (Drag)")
        #expect(try fork.indString(256, 2) == "by Duane Blehm")
        let wind = try fork.window(128)
        #expect(wind.boundsRect.width == 503 && wind.boundsRect.height == 310)
        #expect(try fork.control(129).title == "BEGIN")
        #expect(try fork.control(132).title == "LEVEL")
        #expect(try fork.menu(257).items.map(\.text) ==
                ["Sound", "Reset HiScore", "Help..", "Set Speed..", "Source Code..", "OffScreen.."])
        #expect(try fork.menu(258).title == "(Backspace to Exit)")
    }

    @Test func aboutDialogItems() throws {
        let items = try fork.itemList(130)
        #expect(items.count == 9)
        #expect(items[2].kind == .button && items[2].text == "DONE")
        #expect(items[3].kind == .button && items[3].text == "BackFlip")
        #expect(items[7].kind == .icon && items[7].resourceID == 130)
    }

    @Test func appIconShowsTheICNBitsBlackOnWhite() throws {
        let icon = try fork.iconList(129).icon
        // 32 px: the icon 1:1, black where the ICN# is black, opaque white elsewhere
        // (the plate's rounded corners clip both).
        let px32 = appIconPixels(icon: icon, size: 32)
        for y in 0..<32 {
            for x in 0..<32 {
                let i = (y * 32 + x) * 4
                let inCorner = (x < 8 || x >= 24) && (y < 8 || y >= 24)   // rounded plate corners
                guard !inCorner else { continue }
                if icon.pixel(x, y) != 0 {
                    #expect(px32[i] == 0 && px32[i + 3] == 255)
                } else {
                    #expect(px32[i] == 255 && px32[i + 3] == 255)
                }
            }
        }
        // The ground bar's end pixel at the very corner is clipped to the plate.
        #expect(icon.pixel(0, 31) != 0)
        #expect(px32[(31 * 32 + 0) * 4 + 3] == 0)
        // 1024 px: the largest whole-pixel scale that keeps the whole icon (bar ends
        // included) inside the rounded plate, so every ICN# black pixel is opaque black.
        let px1024 = appIconPixels(icon: icon, size: 1024)
        var k = 0
        for scale in stride(from: 25, through: 1, by: -1) {
            let o = (1024 - 32 * scale) / 2
            let ok = (0..<32).allSatisfy { y in (0..<32).allSatisfy { x in
                icon.pixel(x, y) == 0 || {
                    let i = ((o + y * scale + scale / 2) * 1024 + o + x * scale + scale / 2) * 4
                    return px1024[i] == 0 && px1024[i + 3] == 255
                }()
            } }
            if ok { k = scale; break }
        }
        #expect(k >= 20, "the icon should stay large on the 824 plate (scale \(k))")
        let o = (1024 - 32 * k) / 2
        let blackCount = stride(from: 0, to: px1024.count, by: 4).filter { px1024[$0] == 0 && px1024[$0 + 3] == 255 }.count
        let icnBlack = icon.pixels.filter { $0 != 0 }.count
        #expect(blackCount == icnBlack * k * k, "no black pixel clipped (scale \(k), origin \(o))")
        #expect(px1024[3] == 0)
    }

    @Test func packBits() {
        // Apple Tech Note 1023 example.
        let packed: [UInt8] = [0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A, 0xFD, 0xAA, 0x03, 0x80, 0x00, 0x2A, 0x22, 0xF7, 0xAA]
        let expected: [UInt8] = [0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0xAA, 0xAA, 0xAA, 0xAA, 0x80, 0x00,
                                 0x2A, 0x22, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA]
        #expect(unpackBits(packed, expected: 24) == expected)
    }
}

@MainActor
@Suite struct QuickDrawTests {
    func qd(_ w: Int = 32, _ h: Int = 32) -> QuickDraw {
        QuickDraw(port: GrafPort(size: Rect(top: 0, left: 0, bottom: h, right: w)))
    }

    @Test func randomMatchesTheROMSequence() {
        let q = qd()
        #expect((0..<8).map { _ in q.Random() } == [16807, 15089, -21287, 3114, -18558, -9528, -28968, 2558])
    }

    @Test func mapPtAtMouseRectCornersAndCenter() {
        let src = Rect(left: 210, top: 134, right: 302, bottom: 206)
        let dst = Rect(left: -4, top: -3, right: 4, bottom: 4)
        func map(_ h: Int, _ v: Int) -> Point { var p = Point(h: h, v: v); MapPt(&p, src, dst); return p }
        #expect(map(210, 134) == Point(h: -4, v: -3))
        #expect(map(302, 206) == Point(h: 4, v: 4))
        #expect(map(256, 170) == Point(h: 0, v: 0))
    }

    @Test func regionOperations() {
        let a = Region(rect: Rect(left: 0, top: 0, right: 10, bottom: 10))
        let b = Region(rect: Rect(left: 5, top: 5, right: 15, bottom: 15))
        let u = Region(), d = Region(), s = Region()
        UnionRgn(a, b, u)
        DiffRgn(a, b, d)
        SectRgn(a, b, s)
        #expect(u.rgnBBox == Rect(left: 0, top: 0, right: 15, bottom: 15))
        #expect(PtInRgn(Point(h: 12, v: 12), u) && !PtInRgn(Point(h: 12, v: 2), u))
        #expect(PtInRgn(Point(h: 2, v: 7), d) && !PtInRgn(Point(h: 7, v: 7), d))
        #expect(s.rgnBBox == Rect(left: 5, top: 5, right: 10, bottom: 10))
        OffsetRgn(s, -5, 1)
        #expect(s.rgnBBox == Rect(left: 0, top: 6, right: 5, bottom: 11))
        InsetRgn(d, -1, 0)
        #expect(d.rgnBBox == Rect(left: -1, top: 0, right: 11, bottom: 10))
        #expect(d.spans(atY: 7) == [-1, 6])
        // CopyRgn copies; later changes don't alias.
        let c = Region()
        CopyRgn(a, c)
        OffsetRgn(a, 100, 0)
        #expect(c.rgnBBox == Rect(left: 0, top: 0, right: 10, bottom: 10))
    }

    @Test func copyBitsModesAndMask() {
        let q = qd()
        let src = BitMap(bounds: Rect(left: 0, top: 0, right: 4, bottom: 1))
        src.pixels = [1, 0, 1, 0]
        let dst = q.thePort.portBits
        q.FillRect(Rect(left: 0, top: 0, right: 4, bottom: 1), black)
        q.CopyBits(src, dst, src.bounds, src.bounds, srcCopy, nil)
        #expect(Array(dst.pixels[0..<4]) == [1, 0, 1, 0])
        q.FillRect(Rect(left: 0, top: 0, right: 4, bottom: 1), black)
        q.CopyBits(src, dst, src.bounds, src.bounds, srcOr, nil)
        #expect(Array(dst.pixels[0..<4]) == [1, 1, 1, 1])
        q.EraseRect(Rect(left: 0, top: 0, right: 4, bottom: 1))
        let mask = Region(rect: Rect(left: 2, top: 0, right: 4, bottom: 1))
        q.CopyBits(src, dst, src.bounds, src.bounds, srcCopy, mask)
        #expect(Array(dst.pixels[0..<4]) == [0, 0, 1, 0])
    }

    @Test func invertTwiceRestoresAndPatternsAlign() {
        let q = qd(16, 16)
        let r = Rect(left: 0, top: 0, right: 16, bottom: 16)
        q.FillRect(r, gray)
        let before = q.thePort.portBits.pixels
        #expect(before[0] == 1 && before[1] == 0 && before[16] == 0 && before[17] == 1)
        q.InvertRect(r)
        q.InvertRect(r)
        #expect(q.thePort.portBits.pixels == before)
    }

    @Test func clipRgnAndVisRgnLimitDrawing() {
        let q = qd(8, 8)
        q.ClipRect(Rect(left: 0, top: 0, right: 4, bottom: 8))
        q.thePort.visRgn = Region(rect: Rect(left: 0, top: 0, right: 8, bottom: 4))
        q.PaintRect(Rect(left: 0, top: 0, right: 8, bottom: 8))
        let px = q.thePort.portBits.pixels
        #expect(px.filter { $0 == 1 }.count == 16)
        #expect(px[3] == 1 && px[4] == 0 && px[4 * 8] == 0)
    }

    @Test func everyCharacterInTheGameHasAGlyph() throws {
        var text = ""
        for id in [129, 130, 131, 140, 141] {
            for item in try fork.itemList(id) where item.kind != .icon { text += item.text }
        }
        text += "WALKTROTGALLOPHEAVYNORMALOH BOYFLYING0123456789LEVEL " + (try fork.indString(256, 1)) + (try fork.indString(256, 2))
        let font = BitmapFont.chicago12
        #expect(font.ascent == 12 && font.descent == 3 && font.leading == 1)
        #expect(font.hasGlyph(for: "\u{14}"))   // the Apple symbol used in "LEVEL "
        let missing = Set(text.filter { $0 != "\r" && !font.hasGlyph(for: $0) })
        #expect(missing.isEmpty, "no glyph for \(missing.sorted())")
    }

    @Test func helpTextWrapsWithinItsRects() throws {
        // The original DITL text has explicit line breaks sized for Chicago 12;
        // our font must not force extra wrapping.
        let q = qd()
        for item in try fork.itemList(129) where item.kind == .staticText {
            let explicit = item.text.split(separator: "\r", omittingEmptySubsequences: false).count
            #expect(q.wrap(item.text, width: item.rect.width).count <= explicit + 1)
        }
    }
}

@Suite struct SoundDriverTests {
    @Test func freeFormPlaysReqCountMinusHeaderAtItsRate() {
        let d = SoundDriver()
        d.write(SoundDriver.FreeForm(count: FixRatio(1, 2), waveBytes: [UInt8](repeating: 200, count: 100)), reqCount: 106)
        #expect(!d.isDone)
        var buf = [Float](repeating: 0, count: 64)
        // 100 bytes at half rate = 200 native samples ≈ 0.009 s.
        let rate = SoundDriver.nativeRate
        buf.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: 64, outputRate: rate) }
        #expect(!d.isDone)
        var big = [Float](repeating: 0, count: 256)
        big.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: 256, outputRate: rate) }
        #expect(d.isDone)
    }

    @Test func fourToneCountsDurationDownAndTickWaitsStartOnATick() {
        let d = SoundDriver()
        let square = (0..<256).map { $0 < 128 ? UInt8(255) : 0 }
        let rec = SoundDriver.FourTone(duration: 3, rates: [65536, 0, 0, 0], phases: [0, 0, 0, 0],
                                       waves: [square, square, square, square])
        var buf = [Float](repeating: 0, count: 100)
        d.write(rec)
        #expect(d.fourToneTicksRemaining == 3)
        buf.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: 100, outputRate: SoundDriver.nativeRate) }
        #expect(d.fourToneTicksRemaining == 3)   // partway through the first tick
        d.kill()
        #expect(d.fourToneTicksRemaining == 3 && d.isDone)
        // A zero-duration record (what the driver leaves behind) plays nothing.
        var used = rec
        used.duration = 0
        d.write(used)
        buf.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: 2, outputRate: SoundDriver.nativeRate) }
        #expect(d.isDone && d.fourToneTicksRemaining == 0)
        // After "wait a tick", the sound starts on the next tick boundary.
        d.write(rec, atNextTick: true)
        #expect(!d.isDone && d.currentSynth == .idle)
        let toBoundary = Int(SoundDriver.samplesPerTick) + 2
        var big = [Float](repeating: 0, count: toBoundary)
        big.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: toBoundary, outputRate: SoundDriver.nativeRate) }
        #expect(d.currentSynth == .fourTone)
    }

    @Test func fourToneLastsItsDuration() {
        let d = SoundDriver()
        let square = (0..<256).map { $0 < 128 ? UInt8(255) : 0 }
        d.write(SoundDriver.FourTone(duration: 2, rates: [65536, 0, 0, 0], phases: [0, 0, 0, 0],
                                     waves: [square, square, square, square]))
        let samples = Int(2 * SoundDriver.samplesPerTick)
        var buf = [Float](repeating: 0, count: samples - 10)
        buf.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: $0.count, outputRate: SoundDriver.nativeRate) }
        #expect(!d.isDone)
        var more = [Float](repeating: 0, count: 20)
        more.withUnsafeMutableBufferPointer { d.render(into: $0.baseAddress!, frames: 20, outputRate: SoundDriver.nativeRate) }
        #expect(d.isDone)
        d.kill()
        #expect(d.isDone)
    }
}
