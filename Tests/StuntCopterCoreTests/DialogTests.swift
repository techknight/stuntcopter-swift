import ClassicToolbox
@testable import StuntCopterCore
import Testing

@MainActor
@Suite struct DialogTests {
    @Test func aboutBoxBackflipsThenCloses() throws {
        let (game, host) = try makeGame()
        host.modalAnswers = [4, 3]   // BackFlip, then DONE
        game.DoMenuCommand(StuntCopterGame.appleMenu, 1)
        #expect(host.dialogsShown == [130])
        #expect(host.ticks == 150)   // 15 flip frames × 10 ticks
        #expect(host.modalAnswers.isEmpty)
        #expect(matchesGolden(game.AboutDialog.port.portBits, "about"))
    }

    @Test func speedDialogSetsTheSpeedTrap() throws {
        let (game, host) = try makeGame()
        host.modalAnswers = [4, 1]   // SLOW BY 4, OK
        game.DoMenuCommand(StuntCopterGame.optionMenu, 4)
        #expect(game.speedMultiplier == 0.65)
        #expect(game.GetDItemControl(game.SpeedDialog, 4)?.contrlValue == 1)
        #expect(game.GetDItemControl(game.SpeedDialog, 2)?.contrlValue == 0)
        host.modalAnswers = [2, 1]
        game.DoMenuCommand(StuntCopterGame.optionMenu, 4)
        #expect(game.speedMultiplier == 1.0)
        #expect(matchesGolden(game.SpeedDialog.port.portBits, "speed"))
    }

    @Test func helpSourceAndOffscreenDialogs() throws {
        let (game, host) = try makeGame()
        for item in [3, 5, 6] { game.DoMenuCommand(StuntCopterGame.optionMenu, item) }
        #expect(host.dialogsShown == [129, 137, 139])
        #expect(matchesGolden(game.HelpDialog.port.portBits, "help"))
    }

    @Test func soundToggleAndHiScoreReset() throws {
        let (game, host) = try makeGame()
        game.DoMenuCommand(StuntCopterGame.optionMenu, 1)
        #expect(!game.SoundOn && !host.soundChecked)
        host.hiScore = 99
        game.HiScore = 99
        game.DoMenuCommand(StuntCopterGame.optionMenu, 2)
        #expect(game.HiScore == 0 && host.hiScore == 0)
    }
}
