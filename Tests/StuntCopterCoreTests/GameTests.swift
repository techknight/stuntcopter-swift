import AVFoundation
import ClassicToolbox
import Foundation
@testable import StuntCopterCore
import Testing

@MainActor
@Suite struct GameSetupTests {
    @Test func offscreenShapesFitInsideTheOffscreenBitmap() throws {
        let (game, _) = try makeGame()
        let bounds = game.OffScreen.bounds
        var rects = [game.OffScoreBox, game.OffManInWagon, game.OffDriver, game.OffHorse, game.OffHeight, game.OffCross]
        rects += game.OffCopter[1...3] + game.OffWagon[1...3] + game.OffFlip[1...15] + game.OffMan[1...14]
        rects += game.OffNum[0...9] + game.OffCloud[1...3]
        for r in rects {
            #expect(r.intersection(bounds) == r, "\(r) outside \(bounds)")
        }
        #expect(bounds == Rect(top: 0, left: 0, bottom: 261, right: 426))
    }

    @Test func layoutMatchesThePascalArithmetic() throws {
        let (game, _) = try makeGame()
        // {center ScoreBoxRect in Window bottom}: 387×51 in a 503×310 window, 2px up.
        #expect(game.ScoreBoxRect == Rect(top: 257, left: 58, bottom: 308, right: 445))
        #expect(game.FlightRect == Rect(top: 0, left: 0, bottom: 253, right: 503))
        #expect(game.BeginButton.contrlRect == Rect(top: 165, left: 211, bottom: 191, right: 291))
        #expect(game.EndButton.contrlRect == Rect(top: 200, left: 211, bottom: 226, right: 291))
        #expect(game.MouseRect == Rect(top: 134, left: 210, bottom: 206, right: 302))
        #expect(game.CopterBottomLimit == game.WagonRect.top - 10)
    }

    @Test func startupScreenMatchesGolden() throws {
        let (game, _) = try makeGame()
        #expect(matchesGolden(game.myWindow.portBits, "startup"))
        #expect(matchesGolden(game.OffScreen, "offscreen"))
    }

    /// For comparing against the original in an emulator (Tools/diff_frames.swift):
    /// ATTRACT_LOOPS=N ATTRACT_OUT=frame.pbm swift test --filter dumpAttractFrame
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATTRACT_LOOPS"] != nil))
    func dumpAttractFrame() throws {
        let env = ProcessInfo.processInfo.environment
        let (game, _) = try makeGame()
        for _ in 0..<Int(env["ATTRACT_LOOPS"]!)! { game.tick() }
        try pbmData(game.myWindow.portBits).write(to: URL(fileURLWithPath: env["ATTRACT_OUT"] ?? "attract.pbm"))
    }

    @Test func attractModeMatchesGolden() throws {
        let (game, _) = try makeGame()
        for _ in 0..<120 { game.tick() }
        #expect(game.GameUnderWay == false)
        #expect(matchesGolden(game.myWindow.portBits, "attract-120"))
    }
}

@MainActor
@Suite struct GameplayTests {
    /// Clicks BEGIN (mouse down + up inside the button).
    func begin(_ game: StuntCopterGame) {
        let p = Point(h: 250, v: 178)
        game.post(.mouseDown(p))
        game.post(.mouseUp(p))
        game.tick()
    }

    @Test func beginStartsAGame() throws {
        let (game, host) = try makeGame()
        begin(game)
        #expect(game.GameUnderWay)
        #expect(host.cursorHidden)
        #expect(host.messageMenuShown)
        #expect(!host.menusEnabled)
        #expect(game.MenLeft == 5)
        #expect(game.ManStatus == 4)
        #expect(game.WagonSpeed == 1 && game.Gravity == 4)
    }

    @Test func backspaceAndEscapePauseAndResumeRestoresCopterRegion() throws {
        let (game, host) = try makeGame()
        begin(game)
        for _ in 0..<10 { game.tick() }
        let before = game.CopterRgn.rows
        game.post(.keyDown("\u{8}"))
        game.tick()
        #expect(!game.GameUnderWay)
        #expect(!host.cursorHidden)
        #expect(game.Mask == 3)
        // Resume at the same spot as Begin.
        game.post(.mouseDown(Point(h: 250, v: 178)))
        game.post(.mouseUp(Point(h: 250, v: 178)))
        game.tick()
        #expect(game.GameUnderWay)
        #expect(game.CopterRgn.rows == before)
        game.post(.keyDown("\u{1B}"))
        game.tick()
        #expect(!game.GameUnderWay)
    }

    /// Drops a man with the wagon positioned so that he lands `offset` pixels from the
    /// wagon's left edge, then runs until he lands. Returns the resulting ManStatus.
    func drop(_ game: StuntCopterGame, landingOffset offset: Int) -> Int {
        // Freeze the wagon relative to the man: the wagon moves WagonSpeed px/loop.
        game.post(.mouseDown(Point(h: 0, v: 0)))
        game.tick()
        #expect(game.ManStatus == 0)
        let loopsToFall = (game.WagonRect.top - game.ManRect.bottom) / game.Gravity + 2
        let wagonShift = loopsToFall * game.WagonSpeed
        game.WagonRect = game.WagonRect.offsetBy(game.ManRect.left - offset - wagonShift - game.WagonRect.left, 0)
        game.CloudRgn[game.CloudNdx].setEmpty()   // no cloud jitter
        var n = 0
        while game.ManStatus == 0 && n < 500 { game.tick(); n += 1 }
        return game.ManStatus
    }

    @Test(arguments: [(-6, 1), (0, 1), (33, 1), (34, 8), (44, 8), (45, 9), (70, 9), (-7, 2), (71, 2)])
    func landingZones(offset: Int, expected: Int) throws {
        let (game, host) = try makeGame()
        begin(game)
        host.mouse = Point(h: 256, v: 170)   // centered stick: copter hovers
        for _ in 0..<3 { game.tick() }
        #expect(drop(game, landingOffset: offset) == expected)
    }

    /// Runs the game and its Sound Driver together in simulated real time: each loop
    /// takes 1/(30 × loopRateFactor) s, like the 1987 loop on a Mac Plus. Returns the
    /// synthesizer that was sounding, sampled every millisecond.
    func runWithAudio(_ game: StuntCopterGame, _ host: FakeHost, seconds: Double) -> [SoundDriver.Synth] {
        var timeline: [SoundDriver.Synth] = []
        var t = 0.0, audioT = 0.0
        let msSamples = SoundDriver.nativeRate / 1000
        var scratch = [Float](repeating: 0, count: 64)
        while t < seconds {
            game.tick()
            t += 1 / (30 * game.loopRateFactor)
            host.ticks = Int(t * 60)
            while audioT < t {
                scratch.withUnsafeMutableBufferPointer {
                    game.soundDriver.render(into: $0.baseAddress!, frames: Int(msSamples.rounded()), outputRate: SoundDriver.nativeRate)
                }
                timeline.append(game.soundDriver.currentSynth)
                audioT += 0.001
            }
        }
        return timeline
    }

    @Test func landingFanfarePlaysEachNoteOnceWithGapsLikeTheOriginal() throws {
        let (game, host) = try makeGame()
        begin(game)
        for _ in 0..<3 { game.tick() }
        #expect(drop(game, landingOffset: 10) == 1)
        let timeline = runWithAudio(game, host, seconds: 2.5)
        // Collapse to runs of four-tone sound.
        var runs: [(start: Int, length: Int)] = []
        var i = 0
        while i < timeline.count {
            if timeline[i] == .fourTone {
                var j = i
                while j < timeline.count && timeline[j] == .fourTone { j += 1 }
                runs.append((i, j - i))
                i = j
            } else { i += 1 }
        }
        // Notes of 10, 5, 5 and 20 ticks; the second FlipSound[4] has duration 0 (the
        // driver used it up), so the last chord is not repeated.
        #expect(runs.map { Int((Double($0.length) / (1000.0 / 60)).rounded()) } == [10, 5, 5, 20])
        // Gaps between notes: in the original on a Mac Plus, ~10–55 ms (mean ~30).
        let gaps = zip(runs, runs.dropFirst()).map { $1.start - ($0.start + $0.length) }
        #expect(gaps.allSatisfy { $0 >= 1 && $0 <= 75 }, "gaps \(gaps) ms")
        // Then the copter engine comes back.
        if let last = runs.last {
            #expect(timeline[(last.start + last.length)...].contains(.freeForm))
        }
    }

    /// For listening/comparing: FANFARE_WAV=out.wav swift test --filter renderFanfareWAV
    /// (LANDING_OFFSET=-20 renders a splat instead: a miss).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANFARE_WAV"] != nil))
    func renderFanfareWAV() throws {
        let (game, host) = try makeGame()
        begin(game)
        // Let the copter engine get going first, as in a real game.
        for _ in 0..<30 { game.tick() }
        _ = drop(game, landingOffset: Int(ProcessInfo.processInfo.environment["LANDING_OFFSET"] ?? "10")!)
        var samples: [Float] = []
        var t = 0.0, audioT = 0.0
        var chunk = [Float](repeating: 0, count: 48)
        while t < 2.5 {
            game.tick()
            t += 1 / (30 * game.loopRateFactor)
            host.ticks = Int(t * 60)
            while audioT < t {
                chunk.withUnsafeMutableBufferPointer { game.soundDriver.render(into: $0.baseAddress!, frames: 48, outputRate: 48_000) }
                samples += chunk
                audioT += 0.001
            }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, v) in samples.enumerated() { buffer.floatChannelData![0][i] = v }
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: ProcessInfo.processInfo.environment["FANFARE_WAV"]!),
                                   settings: format.settings)
        try file.write(from: buffer)
    }

    @Test func successfulLandingScoresHeightTimesLevel() throws {
        let (game, _) = try makeGame()
        begin(game)
        for _ in 0..<3 { game.tick() }
        _ = drop(game, landingOffset: 10)
        #expect(game.Score == game.HeightOfDrop * 1)
        #expect(game.GoodJumps == 1)
        #expect(game.ThumbState[1] == 1)
    }

    @Test func fiveGoodJumpsAdvanceTheLevel() throws {
        let (game, _) = try makeGame()
        begin(game)
        game.GoodJumps = 5
        game.MenLeft = 1
        game.ResetManHanging()
        #expect(game.CurrentLevel == 2)
        #expect(game.WagonSpeed == 2 && game.Gravity == 4)
        #expect(game.MenLeft == 5)
        #expect(game.GameUnderWay)
        // Levels 3.. speed tops out at GALLOP, then gravity lightens.
        for _ in 0..<5 {
            game.GoodJumps = 5
            game.MenLeft = 1
            game.ResetManHanging()
        }
        #expect(game.WagonSpeed == 3)
        #expect(game.Gravity == 1)
    }

    @Test func fewerThanFiveGoodJumpsEndsTheGame() throws {
        let (game, host) = try makeGame()
        begin(game)
        game.GoodJumps = 4
        game.MenLeft = 1
        game.Score = 42
        game.ResetManHanging()
        #expect(!game.GameUnderWay)
        #expect(game.Mask == 1)
        #expect(game.HiScore == 42)
        #expect(host.hiScore == 42)
        #expect(!host.cursorHidden)
        #expect(game.BeginButton.contrlVis)
    }

    @Test func hittingTheHorseEndsTheGameAfterTheSplat() throws {
        let (game, _) = try makeGame()
        begin(game)
        for _ in 0..<3 { game.tick() }
        #expect(drop(game, landingOffset: 50) == 9)
        var n = 0
        while game.GameUnderWay && n < 100 { game.tick(); n += 1 }
        #expect(!game.GameUnderWay)
        #expect(game.MenLeft == 0)
    }

    @Test func fullGameSnapshot() throws {
        let (game, host) = try makeGame()
        begin(game)
        host.mouse = Point(h: 280, v: 150)
        for i in 0..<400 {
            if i % 60 == 30 { game.post(.mouseDown(Point(h: 0, v: 0))) }
            game.tick()
            host.ticks += 2
        }
        #expect(matchesGolden(game.myWindow.portBits, "play-400"))
    }
}
