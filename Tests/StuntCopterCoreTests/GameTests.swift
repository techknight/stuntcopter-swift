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
