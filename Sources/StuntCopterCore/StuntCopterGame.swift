// StuntCopter 1.5 — Copyright © 1986, 1987 by Duane Blehm.
//
// A line-by-line port of StuntCopter.pas (see original/) onto ClassicToolbox.
// Procedure and variable names are kept from the Pascal so the two can be read
// side by side; arrays keep their Pascal index ranges (element 0 unused where the
// Pascal array starts at 1). Blehm's comments are preserved in {braces} style
// where they explain the "why".

import ClassicToolbox

@MainActor
public final class StuntCopterGame: QuickDraw {
    // MARK: CONST
    let WindResId = 128          // Window Resource
    let CopterId = 128           // PICT resources
    let ManId = 129
    let ScoreBoxId = 130
    let StringID = 256           // String List res.Id
    let HelpId = 129             // Help Dialog resource Id
    let AboutId = 130            // About Stunt Dialog Resource id
    let lastString = 2
    public static let appleMenu = 1
    public static let fileMenu = 256     // Menu Resource Id's
    public static let optionMenu = 257
    public static let messageMenu = 258
    let pressBegin = 129         // Control Resources
    let pressResume = 130
    let pressEnd = 131
    let pressLevel = 132
    let BackSpace: Character = "\u{8}"   // backspace charcode
    let Escape: Character = "\u{1B}"     // modern addition: Esc pauses too

    public weak var host: GameHost?
    public let resources: ResourceFork

    // MARK: VAR
    var SpeedTrapOn = false      // {we'll flag if user wants to slow down}
    var SpeedFactor = 0          // {duration of Delay for slowdowns}
    var myStrings = ["", "", ""]
    public internal(set) var SoundOn = true   // {flag for sound off or on, a menu option}
    public internal(set) var Finished = false // {terminate the program}
    public let myWindow: GrafPort            // {our game window}
    public internal(set) var HelpDialog: ClassicDialog!
    public internal(set) var AboutDialog: ClassicDialog!
    public internal(set) var SourceDialog: ClassicDialog!
    public internal(set) var SpeedDialog: ClassicDialog!
    public internal(set) var BitMapDialog: ClassicDialog!
    var Copter: Picture!, Man: Picture!, ScoreBox: Picture!  // {3 pictures, contain all shapes}
    public internal(set) var OffScreen: BitMap!   // {for drawing into offscreen}
    var OldBits: BitMap!
    // {onscreen destination rects for shapes}
    var CoptRect = Rect.zero, ManRect = Rect.zero, WagonRect = Rect.zero, ScoreBoxRect = Rect.zero
    var NumRect = Rect.zero, ManInWagon = Rect.zero, DriverRect = Rect.zero, HorseRect = Rect.zero
    var FlipRect = [Rect](repeating: .zero, count: 3)     // { destination for flips}
    var FlipFrame = [Rect](repeating: .zero, count: 3)
    var CoptNdx = 0, ManNdx = 0, WagonNdx = 0   // {Shape Index's,which shape to draw}
    var WagonMoving = false                     // {Is wagon moving or stopped?}
    var Dh = 0, Dv = 0                          // {Offset for Copter rectangle/shape}
    var CopterBottomLimit = 0                   // {Can't fly below this point}
    var CrossRect = Rect.zero, OffCross = Rect.zero, YokeLimits = Rect.zero, YokeErase = Rect.zero
    var YokeHt = 0, YokeWdth = 0, MouseHt = 0, MouseWdth = 0, OffsetHt = 0, OffsetWdth = 0
    var CrossHt = 0, CrossWdth = 0, DeltaHt = 0, DeltaWdth = 0, ManWdth = 0, ManHt = 0
    var MaskRgn: Region!                        // {mask out for yoke in scorebox}
    var BorderRect = Rect.zero                  // {limits of copter.topleft on screen}
    var MouseRect = Rect.zero                   // {limit mouse movement to this rect}
    var DeltaRect = Rect.zero                   // {map rect for copter control;dh,dv}

    // {'source' rectangles,in offscreen bitmap}
    var OffCopter = [Rect](repeating: .zero, count: 4)
    var OffMan = [Rect](repeating: .zero, count: 15)
    var OffWagon = [Rect](repeating: .zero, count: 4)
    var OffScoreBox = Rect.zero
    var OffNum = [Rect](repeating: .zero, count: 10)
    var OffFlip = [Rect](repeating: .zero, count: 16)
    var OffManInWagon = Rect.zero
    var OffDriver = Rect.zero, OffHorse = Rect.zero
    var OffHeight = Rect.zero
    var HeightOfDrop = 0
    public internal(set) var Score = 0
    var Height = 0
    public internal(set) var HiScore = 0 {    // {the sky's the limit...}
        didSet { if HiScore != oldValue { host?.hiScoreChanged(HiScore) } }
    }
    public internal(set) var MenLeft = 0
    public internal(set) var GoodJumps = 0
    public internal(set) var WagonSpeed = 0
    public internal(set) var Gravity = 0
    var HeightStr = ""                          // {drawn into scorebox}
    var HeightPt = Point.zero                   // {'moveto' location for HeightStr}
    public internal(set) var ManStatus = 0       // {0=drop 1=flip 2=splat 4=hang 8=hitdriver 9=hithorse}
    var HtStatRect = Rect.zero, WagStatRect = Rect.zero, GravStatRect = Rect.zero
    var ScoreMan = [Rect](repeating: .zero, count: 6)    // {man indicator in scorebox}
    var ThumbUp = [Rect](repeating: .zero, count: 6)     // { boxes for thumbs up }
    var ThumbDown = [Rect](repeating: .zero, count: 6)
    var ThumbState = [Int](repeating: 0, count: 6)       // {0=none 1=up 2=down}
    var ScoreNum = [Rect](repeating: .zero, count: 7)    // { boxes to record score digits}
    var HiScoreNum = [Rect](repeating: .zero, count: 7)
    public internal(set) var BeginButton: Control!
    public internal(set) var ResumeButton: Control!
    public internal(set) var EndButton: Control!
    public internal(set) var LevelButton: Control!
    var LevelOnDisplay = false                  // {is level button being shown?}
    var LevelUnion: Region!                     // {used to mask levelbutton from copter drawarea}
    public internal(set) var GameUnderWay = false // {is game under way?}
    var FlightRect = Rect.zero                  // {window area less the scorebox stuff}
    var WagonStatus = ["", "", "", ""]          // {wagonspeed to scorebox}
    var GravityStatus = ["", "", "", "", ""]    // {gravity to scorebox}
    var FlightRgn: [Region] = []                // {mask buttons from FlightRect}
    var BeginRgn: Region!, EndRgn: Region!
    public internal(set) var Mask = 0            // {which mask is in use?}
    var LevelTimer = 0                          // {time how long to show levelbutton}
    var aTick = 0
    public internal(set) var CurrentLevel = 0
    var FlipCount = 0                           // {index flip and splat shapes}
    var FlipTime = [0, 10, 5, 5, 20]            // {duration for flip sounds}
    // {cloudstuff}
    var CloudPic: [Picture?] = [nil, nil, nil, nil]      // {Cloud pictures}
    var CloudRgn: [Region] = []                          // {Cloud Regions}
    var OffCloud = [Rect](repeating: .zero, count: 4)    // {Cloud Rect's in offScreen}
    var Cloud = [Rect](repeating: .zero, count: 4)       // {Destination Rects}
    var CopterRgn: Region!                               // {will use to mask Copter CopyBits}
    var tempRgn: Region!
    var CloudNdx = 0
    var CloudOnDisplay = false  // {for DrawUpdate to flag if cloud need be drawn}

    // {Sound varibles}
    public let soundDriver = SoundDriver()
    var CoptBuff = 0, SplatBuff = 0             // {Sound buffers}
    var CoptSound: SoundDriver.FreeForm!        // {FreeForm synthesizer sound}
    var SplatSound: SoundDriver.FreeForm!
    var FlipSound: [SoundDriver.FourTone] = []  // {four FourTone Sounds}
    var FlipSynthSndRec = 1                     // {FlipSynth^.sndRec: which FlipSound}
    enum SoundBuffer { case copt, splat, flipSynth }
    var SoundParmBlk = (iobuffer: SoundBuffer.copt, ioreqcount: 0)   // {used for PBWrite}
    var WhichSound = 0                          // {which sound is being played?}
    var Squarewave = [UInt8](repeating: 0, count: 256)

    // MARK: Modern plumbing
    var eventQueue: [GameEvent] = []
    var trackingControl: Control?               // {TrackControl in progress}
    var messageMenuShown = false
    var menusEnabled = true

    /// Relative game speed chosen in the Set Speed dialog (replaces Delay()).
    public var speedMultiplier: Double {
        guard SpeedTrapOn else { return 1.0 }
        return SpeedFactor == 1 ? 0.8 : 0.65
    }

    /// How fast the main loop should run relative to the in-game baseline. The 1987
    /// loop was CPU-bound; timed on an emulated Mac Plus (Tools/measure_wagon.swift) it
    /// did ~30 loops/s in play and ~60 in the lighter attract/pause loop. Blehm notes
    /// "freeform sound slows the program by about 20%", so play is faster with sound off.
    public var loopRateFactor: Double {
        let native = GameUnderWay ? (SoundOn ? 1.0 : 1.2) : 2.0
        return native * speedMultiplier
    }

    /// Window content size (from the 'WIND' resource).
    public var windowRect: Rect { myWindow.portRect }

    public init(host: GameHost?, resources: ResourceFork? = nil) throws {
        let res = try resources ?? ResourceFork(forkData: EmbeddedResources.stuntCopterFork)
        self.resources = res
        let wind = try res.window(128)
        let b = wind.boundsRect
        myWindow = GrafPort(size: Rect(top: 0, left: 0, bottom: b.height, right: b.width))
        self.host = host
        super.init(port: myWindow)
    }

    /// The window's global position in 1987 (below the menu bar, custom WDEF).
    public var windowGlobalOrigin: Point {
        (try? resources.window(WindResId).boundsRect.topLeft) ?? Point(h: 4, v: 30)
    }

    // MARK: - Procedures

    func LevelToButtonTitle(_ aLevel: Int) {
        // {put level number into LevelButton title, 2 digits only}
        let Digit: Character = "\u{14}"   // {this is the 'apple'}
        SetCTitle(LevelButton, "LEVEL " + String(Digit) + String(aLevel))
    }

    func DrawWagonStatus() {
        // {gravity and wagonspeed into scorebox,each new level}
        var h = (WagStatRect.left + WagStatRect.right - StringWidth(WagonStatus[WagonSpeed])) / 2
        MoveTo(h, WagStatRect.bottom - 2)   // {locate string in center of rect}
        EraseRect(WagStatRect)
        DrawString(WagonStatus[WagonSpeed])
        h = (GravStatRect.left + GravStatRect.right - StringWidth(GravityStatus[Gravity])) / 2
        MoveTo(h, GravStatRect.bottom - 2)
        EraseRect(GravStatRect)
        DrawString(GravityStatus[Gravity])
    }

    func DrawScoreIntoBox(_ aScore: Int, _ WhereRect: [Rect]) {
        // {given a score or hiscore write it into the scorebox, using number
        // shapes from offscreen bitmap}
        var Digit = [Int](repeating: 0, count: 7)
        Digit[6] = 0   // {one's digit always zero}
        Digit[5] = aScore % 10
        Digit[4] = (aScore / 10) % 10
        Digit[3] = (aScore / 100) % 10
        Digit[2] = (aScore / 1000) % 10
        Digit[1] = (aScore / 10000) % 10
        for i in 1...6 {   // {OffNum are offScreen numeral shapes 0 to 9}
            CopyBits(OffScreen, myWindow.portBits, OffNum[Digit[i]], WhereRect[i], srcCopy, nil)
        }
    }

    func CreateRegions() {
        FlightRgn = (0...4).map { _ in NewRgn() }
        CopterRgn = NewRgn()
        tempRgn = NewRgn()
        BeginRgn = NewRgn()
        EndRgn = NewRgn()
        LevelUnion = NewRgn()
    }

    func InitialSoundRates() {   // {reset pitch of four flipsounds, start of each game}
        for i in 1...4 {
            FlipSound[i].rates[0] = 29316
            FlipSound[i].rates[1] = i > 1 ? 78264 : 0
            FlipSound[i].rates[2] = i > 2 ? 98607 : 0
            FlipSound[i].rates[3] = i > 3 ? 117264 : 0
        }
    }

    func CreateStrings() {   // {i-468, get all the strings from resource file}
        for i in 1...lastString { myStrings[i] = (try? resources.indString(StringID, i)) ?? "" }
    }

    func DrawAString(_ theString: String, _ h: Int, _ v: Int) {
        MoveTo(h, v)
        DrawString(theString)
    }

    func DrawAllmyStrings() {
        TextFace([bold, underline])
        DrawAString(myStrings[1], (504 - StringWidth(myStrings[1])) / 2, 60)   // {centered}
        TextFace([])
        DrawAString(myStrings[2], (504 - StringWidth(myStrings[2])) / 2, 80)
        // {lets draw a cloud}
        var tRect = Cloud[3]   // {this is a cloud rect, lets draw one of our clouds}
        OffsetRect(&tRect, 256 - tRect.left, 30 - tRect.top)   // {locate it on the screen}
        // {now draw it with 'srcOr' mode so we won't disturb our text}
        CopyBits(OffScreen, myWindow.portBits, OffCloud[3], tRect, srcOr, nil)
    }

    func CreateSound() {
        // {we're writing direct to the sound driver with PBWrite... the copter engine
        // is a freeform sound, the fanfare played for a good jump is 4 fourtone
        // sounds, and the splat is a freeform sound.}
        CoptBuff = 7406   // { Create the Copter sound stuff,6 bytes for mode & count}
        var wave = [UInt8](repeating: 127, count: CoptBuff - 6)   // {set all to 127}
        CoptBuff = CoptBuff - 7   // {this is size of WaveForm array'0-7399'}
        var j = 0
        while j <= CoptBuff {
            let i = abs(Random()) / 512   // {random number 0 to 64}
            wave[j] = UInt8(i)            // {fill up the buffer with copter sound}
            if j % 370 == 100 {
                j += 200
                wave[j] = 255
                j += 70
            } else {
                j += 1
            }
        }
        CoptSound = SoundDriver.FreeForm(count: FixRatio(1, 6), waveBytes: wave)   // {fixed point notation}

        SplatBuff = 1486   // { Create the Splat sound stuff }
        var splat = [UInt8](repeating: 0, count: SplatBuff - 6)
        SplatBuff = SplatBuff - 7   // {this is size of WaveForm array '0-1479'}
        j = 0
        var i = 0
        while j <= SplatBuff {
            splat[j] = UInt8(i)                // {fill up the buffer}
            if i < 255 { i += 1 } else { i = 0 }   // {Sawtooth wave form}
            j += 1
        }
        SplatSound = SoundDriver.FreeForm(count: FixRatio(1, 2), waveBytes: splat)

        for k in 0...127 {   // {describe a squarewave form for flip sound}
            Squarewave[k] = 255
            Squarewave[k + 128] = 0
        }
        // {Build the four FourToneSndRecords; phases out of phase just for fun}
        FlipSound = (0...4).map { k in
            SoundDriver.FourTone(duration: FlipTime[k], rates: [0, 0, 0, 0], phases: [64, 192, 128, 0],
                                 waves: [Squarewave, Squarewave, Squarewave, Squarewave])
        }
        // {remember must InitialSoundRates each game,at BeginButton press}
        WhichSound = 0
        SoundParmBlk = (.copt, CoptBuff)   // {will Start coptersound when game begins,MainEventLoop}
    }

    /// PBWrite(SoundParmBlk, true): start whatever the parameter block points at.
    func PBWrite() {
        switch SoundParmBlk.iobuffer {
        case .copt: soundDriver.write(CoptSound, reqCount: SoundParmBlk.ioreqcount)
        case .splat: soundDriver.write(SplatSound, reqCount: SoundParmBlk.ioreqcount)
        case .flipSynth: soundDriver.write(FlipSound[FlipSynthSndRec])
        }
    }

    func PBKillIO() { soundDriver.kill() }

    func CreateWindow() {   // {windows,dialogs, and controls}
        HelpDialog = try? ClassicDialog(id: HelpId, resources: resources)
        AboutDialog = try? ClassicDialog(id: AboutId, resources: resources)
        // {our new dialogs}
        SourceDialog = try? ClassicDialog(id: 137, resources: resources)
        SpeedDialog = try? ClassicDialog(id: 138, resources: resources)
        if let c = GetDItemControl(SpeedDialog, 2) { SetCtlValue(c, 1) }   // {click the Normal Box}
        SpeedTrapOn = false
        BitMapDialog = try? ClassicDialog(id: 139, resources: resources)

        func control(_ id: Int) -> Control {
            let t = try! resources.control(id)
            return Control(template: t, owner: myWindow)
        }
        BeginButton = control(pressBegin)
        ResumeButton = control(pressResume)
        EndButton = control(pressEnd)
        LevelButton = control(pressLevel)

        LevelOnDisplay = false   // { flag when level is displayed}
        // {locate the control buttons in the center of myWindow.. Begin and Resume
        // are in same location as are End and Level}
        let width = myWindow.portRect.right - myWindow.portRect.left
        let h = myWindow.portRect.left + ((width - 80) / 2)   // {center control}
        var v = 165
        SizeControl(BeginButton, 80, 26); MoveControl(BeginButton, h, v)
        SizeControl(ResumeButton, 80, 26); MoveControl(ResumeButton, h, v)
        SetRectRgn(BeginRgn, h, v, h + 80, v + 26)   // { BeginButton rect. region }
        v = 200
        SizeControl(EndButton, 80, 26); MoveControl(EndButton, h, v)
        SizeControl(LevelButton, 80, 26); MoveControl(LevelButton, h, v)
        SetRectRgn(EndRgn, h, v, h + 80, v + 26)
        CopyRgn(EndRgn, LevelUnion)
        OffsetRgn(LevelUnion, -1, 0)   // {used to mask level on scrolling CopterRgn}
    }

    func CreatePictures() throws {   // {get 3 PICT's from resource file}
        Copter = try resources.picture(CopterId)   // {contains 3 Copters,3 Wagons,14 Flips}
        CoptRect = Copter.picFrame                 // { i-159 }
        Man = try resources.picture(ManId)         // {contains 12 Men,2 thumbs,10 numbers,Cross,etc.}
        ManRect = Man.picFrame
        ScoreBox = try resources.picture(ScoreBoxId)   // {Score,status,yoke control,etc.}
        ScoreBoxRect = ScoreBox.picFrame
        // {cloudstuff}
        CloudRgn = [NewRgn()]
        for i in 1...3 {
            CloudPic[i] = try resources.picture(i + 355)   // {the three cloud pictures}
            Cloud[i] = CloudPic[i]!.picFrame               // {set the cloud Rects size}
            OffCloud[i] = Cloud[i]
            CloudRgn.append(try resources.region(i + 355)) // {regions for clouds}
            // {enlarge region so we can mask just inside it as we move to the left}
            InsetRgn(CloudRgn[i], -1, 0)
        }
    }

    func CreateOffScreenBitMap() {   // {see CopyBits stuff,also tech.note 41}
        let OffLeft = 0, OffTop = 0, OffRight = 426
        let OffBottom = 261   // {size bitmap to contain all six PICTs}
        OffScreen = BitMap(bounds: Rect(left: OffLeft, top: OffTop, right: OffRight, bottom: OffBottom))
    }

    func DrawPicsIntoOffScreen() {
        OldBits = myWindow.portBits   // {preserve old BitMap}
        SetPortBits(OffScreen)        // { our new BitMap }
        FillRect(myWindow.portRect, white)   // {erase our new BitMap to white}

        OffsetRect(&ScoreBoxRect, -ScoreBoxRect.left, -ScoreBoxRect.top)
        DrawPicture(ScoreBox, ScoreBoxRect)   // { ScoreBox stuff }
        OffsetRect(&CoptRect, -CoptRect.left, ScoreBoxRect.bottom - CoptRect.top)   // {below ScoreBox}
        DrawPicture(Copter, CoptRect)
        OffsetRect(&ManRect, CoptRect.right - ManRect.left, ScoreBoxRect.bottom - ManRect.top)
        DrawPicture(Man, ManRect)   // { right of Copter,below ScoreBox }

        SetPortBits(OldBits)   // {restore old bitmap}
    }

    func DrawCloudsIntoOffScreen() {   // {draw the 3 clouds into offscreen}
        OldBits = myWindow.portBits
        SetPortBits(OffScreen)

        OffsetRect(&OffCloud[3], -OffCloud[3].left, OffFlip[14].bottom - OffCloud[3].top)   // {left side,below flips}
        DrawPicture(CloudPic[3]!, OffCloud[3])

        OffsetRect(&OffCloud[1], OffCross.right - OffCloud[1].left, OffHorse.bottom - OffCloud[1].top)   // {right of cross,below deadhorse}
        DrawPicture(CloudPic[1]!, OffCloud[1])

        OffsetRect(&OffCloud[2], OffCloud[3].right - OffCloud[2].left, OffCloud[1].bottom - OffCloud[2].top)   // {right of cloud3,below cloud1}
        DrawPicture(CloudPic[2]!, OffCloud[2])

        // {let's shrink our cloud borders...leave one pixel border on right side,
        // this will limit cloud movement to left only!}
        // {so now CloudRgn[]^^.RgnBBox.topleft will be same as Cloud[].topleft}
        for i in 1...3 {
            InsetRect(&OffCloud[i], 1, 1); OffCloud[i].right += 1
            InsetRect(&Cloud[i], 1, 1); Cloud[i].right += 1
        }

        SetPortBits(OldBits)
    }

    func CreateOffScreenRects() {
        // { where are all those shapes? locate all the shapes in the OffScreen bitmap
        // by defining the rectangles that contain them. }
        OffScoreBox = ScoreBoxRect   // {Scorebox is easy... already upper left}

        // {find the 3 copters}
        var tRect = CoptRect         // {here CoptRect is the whole Copter PICT.frame}
        tRect.right = tRect.left + 74    // { width of one copter }
        tRect.bottom = tRect.top + 26    // { height of copter }
        for i in 1...3 {
            OffCopter[i] = tRect
            OffsetRect(&tRect, 74, 0)    // { 3 copters in a row }
        }
        CoptRect = OffCopter[1]      // {now CoptRect is set to size of first copter}

        // {find the 3 wagons}
        tRect.left = CoptRect.left   // {left edge of OffScreen}
        tRect.top = CoptRect.bottom  // {3 wagons are just below copters}
        tRect.right = tRect.left + 73    // { width of one wagon }
        tRect.bottom = tRect.top + 22    // { height of wagon }
        for i in 1...3 {
            OffWagon[i] = tRect
            OffsetRect(&tRect, 73, 0)    // { 3 wagons in a row }
        }
        WagonRect = OffWagon[1]      // {Size onscreen rect}

        // {find the 14 flip shapes}
        tRect.left = WagonRect.left  // { topleft corner for reference }
        tRect.top = WagonRect.bottom // {2 rows of 7 Flips just below wagons}
        tRect.right = tRect.left + 32    // { width of one manflip }
        tRect.bottom = tRect.top + 41    // { height of manflip }
        for i in 1...7 {
            OffFlip[i] = tRect           // { 7 in top row }
            OffsetRect(&tRect, 0, 41)
            OffFlip[i + 7] = tRect       // { 7 in bottom row }
            OffsetRect(&tRect, 32, -41)
        }
        OffFlip[15] = OffFlip[1]     // { complete animation back to 'stand up' }
        for i in 1...2 { FlipRect[i] = tRect }   // {Size onscreen Rects}

        // {find men hanging,dropping,splat and thumb up/down shapes}
        tRect = ManRect              // {upper left corner of Man Picture}
        tRect.right = tRect.left + 14    // { width of one man }
        tRect.bottom = tRect.top + 16    // { height of man }
        for i in 1...7 {
            OffMan[i] = tRect            // {7 in toprow,1=manhanging,2-6=dropping,7=thumbup}
            OffsetRect(&tRect, 0, 16)
            OffMan[i + 7] = tRect        // {7 in bottom row,1-6=splat,7th=thumbdown}
            OffsetRect(&tRect, 14, -16)
        }
        ManRect = OffMan[1]
        ManHt = ManRect.bottom - ManRect.top
        ManWdth = ManRect.right - ManRect.left

        // {find the 10 numeral shapes used for score}
        tRect.left = ManRect.left
        tRect.top = OffMan[8].bottom     // {2 rows of 5 numerals below men}
        tRect.right = tRect.left + 20    // {width of one number}
        tRect.bottom = tRect.top + 15    // { height of number }
        for i in 0...4 {
            OffNum[i] = tRect            // { 5 numerals '0-4'in top row }
            OffsetRect(&tRect, 0, 15)
            OffNum[i + 5] = tRect        // { 5 numerals '5-9' in bottom row }
            OffsetRect(&tRect, 20, -15)
        }
        NumRect = tRect

        tRect.left = ManRect.left    // {cross/yoke in scorebox shows mouse movements}
        tRect.top = OffNum[5].bottom // {cross/yoke is below numerals}
        tRect.right = tRect.left + 81
        tRect.bottom = tRect.top + 81    // { height of cross/yoke }
        OffCross = tRect
        CrossRect = tRect

        tRect.top = OffCross.top     // {ManInWagon is drawn for safe landing}
        tRect.left = OffCross.right
        tRect.bottom = tRect.top + 10
        tRect.right = tRect.left + 28
        OffManInWagon = tRect
        ManInWagon = tRect

        tRect.top = OffManInWagon.bottom   // {Driver is drawn if driver is hit}
        tRect.bottom = tRect.top + 22
        tRect.left = OffCross.right
        tRect.right = tRect.left + 40
        OffDriver = tRect
        DriverRect = OffDriver

        tRect.top = OffDriver.bottom   // {Horse is drawn if horse is hit}
        tRect.bottom = tRect.top + 22
        tRect.left = OffCross.right
        tRect.right = tRect.left + 29
        OffHorse = tRect
        HorseRect = OffHorse
    }

    // MARK: Dialogs

    func ShowWindow(_ d: ClassicDialog) {
        ShowDialog(d)
        host?.showDialogWindow(d)
    }

    func HideWindow(_ d: ClassicDialog) {
        HideDialog(d)
        host?.hideDialogWindow(d)
    }

    func ModalDialog(_ d: ClassicDialog) -> Int { host?.modalDialog(d) ?? 1 }

    func DisplayHelpDialog() {
        ShowWindow(HelpDialog)
        _ = ModalDialog(HelpDialog)   // {We'll close it not matter what was hit}
        HideWindow(HelpDialog)
    }

    func DisplayAboutDialog() {   // { display the About Stunt... dialog window}
        let tPort = GetPort()
        ShowWindow(AboutDialog)
        SetPort(AboutDialog.port)   // {so we can draw into our window}

        var tRect = FlipRect[1]
        tRect.right = 2 * (tRect.right - tRect.left) + tRect.left   // {enlarge 4 times}
        tRect.bottom = 2 * (tRect.bottom - tRect.top) + tRect.top
        OffsetRect(&tRect, AboutDialog.port.portRect.right - 40 - tRect.right,
                   AboutDialog.port.portRect.top + 54 - tRect.top)
        var fRect = tRect
        InsetRect(&fRect, -2, -2)
        FrameRect(fRect)
        InsetRect(&fRect, -1, -1)   // {draw a frame for the enlarged flip}
        FrameRect(fRect)
        InsetRect(&fRect, -2, -2)
        FrameRoundRect(fRect, 8, 8)
        FillRect(tRect, gray)

        fRect = Cloud[3]   // {this is a cloud rect, lets draw one of our clouds}
        OffsetRect(&fRect, 120 - fRect.left, -12 - fRect.top)
        CopyBits(OffScreen, AboutDialog.port.portBits, OffCloud[3], fRect, srcOr, nil)

        var itemHit: Int
        repeat {
            itemHit = ModalDialog(AboutDialog)   // {find which button hit,OK or BACKFLIP}
            if itemHit == 4 {   // { do a backflip }
                for i in 1...15 {
                    CopyBits(OffScreen, AboutDialog.port.portBits, OffFlip[i], tRect, srcCopy, nil)
                    host?.pause(ticks: 10)   // {pause...}
                }
                FillRect(tRect, gray)   // {erase the last flipshape}
            }
        } while !(itemHit == 3 || itemHit == 1)   // {the done button or 'enter' key}
        HideWindow(AboutDialog)
        SetPort(tPort)
    }

    func DisplaySourceDialog() {
        let tPort = GetPort()
        ShowWindow(SourceDialog)
        SetPort(SourceDialog.port)
        _ = ModalDialog(SourceDialog)   // {close it no matter what was hit}
        HideWindow(SourceDialog)
        SetPort(tPort)
    }

    func DisplayBitMapDialog() {
        let tPort = GetPort()
        ShowWindow(BitMapDialog)
        SetPort(BitMapDialog.port)
        CopyBits(OffScreen, BitMapDialog.port.portBits, OffScreen.bounds, OffScreen.bounds, srcCopy, nil)
        _ = ModalDialog(BitMapDialog)
        HideWindow(BitMapDialog)
        SetPort(tPort)
    }

    func SetControlValue(_ which: Int) {
        for i in 2...4 {
            guard let c = GetDItemControl(SpeedDialog, i) else { continue }
            SetCtlValue(c, i == which ? 1 : 0)
        }
    }

    func DisplaySpeedDialog() {
        let tPort = GetPort()
        ShowWindow(SpeedDialog)
        SetPort(SpeedDialog.port)
        var itemHit: Int
        repeat {
            itemHit = ModalDialog(SpeedDialog)
            switch itemHit {
            case 2:
                SetControlValue(2)
                SpeedTrapOn = false
            case 3:
                SetControlValue(3)
                SpeedFactor = 1
                SpeedTrapOn = true
            case 4:
                SetControlValue(4)
                SpeedFactor = 2
                SpeedTrapOn = true
            default:
                break
            }
        } while itemHit != 1
        HideWindow(SpeedDialog)
        SetPort(tPort)
    }

    // MARK: Menus

    /// DoMenuCommand(mResult) with the menu ID and item already split out.
    public func DoMenuCommand(_ theMenu: Int, _ theItem: Int) {
        switch theMenu {
        case Self.appleMenu:
            let tPort = GetPort()
            if theItem == 1 { DisplayAboutDialog() }   // {desk accessories are gone}
            SetPort(tPort)
        case Self.fileMenu:
            Finished = true   // {quit this program}
            CloseStuff()
            host?.quit()
        case Self.optionMenu:
            switch theItem {
            case 1:   // {toggle sound on or off}
                SoundOn.toggle()
                host?.checkSoundItem(SoundOn)
            case 2:   // {reset hiscore}
                HiScore = 0
                DrawScoreIntoBox(HiScore, HiScoreNum)
            case 3: DisplayHelpDialog()
            case 4: DisplaySpeedDialog()
            case 5: DisplaySourceDialog()
            case 6: DisplayBitMapDialog()   // {show our pics and shapes}
            default: break
            }
        default:
            break
        }
    }

    func DrawMenuBar() { host?.drawMenuBar(messageMenuShown: messageMenuShown, menusEnabled: menusEnabled) }

    // MARK: Game

    func StartNewCloud() {
        // {get one of 3 clouds, locate at right of screen,do all the rgn stuff}
        if CloudNdx < 3 { CloudNdx += 1 } else { CloudNdx = 1 }   // {get the next cloud}
        let CloudHeight = abs(Random()) / 256   // {random between 0 and 128}
        OffsetRect(&Cloud[CloudNdx], 512 - Cloud[CloudNdx].left, CloudHeight - Cloud[CloudNdx].top)
        OffsetRgn(CloudRgn[CloudNdx], 512 - CloudRgn[CloudNdx].rgnBBox.left,
                  CloudHeight - CloudRgn[CloudNdx].rgnBBox.top)
        // {define region copter can be drawn in...will move with cloud}
        var tRect = FlightRect
        tRect.right = Cloud[CloudNdx].right + 514   // {a screen width beyond cloud}
        RectRgn(tempRgn, tRect)
        DiffRgn(tempRgn, CloudRgn[CloudNdx], CopterRgn)   // {cloud out of the Copter area}
    }

    func InitialCopterStuff() {
        OffsetRect(&CoptRect, 212 - CoptRect.left, 110 - CoptRect.top)   // {dest. - source}
        CoptNdx = 1
        OffsetRect(&WagonRect, -WagonRect.left, ScoreBoxRect.top - 4 - WagonRect.bottom)

        WagonNdx = 1         // {set index to first wagon shape}
        WagonMoving = true
        ManNdx = 1           // {this is the man hanging}
        Dh = 0; Dv = 0       // { no initial copter movement }

        Score = 0
        MenLeft = 5          // { # of men/level }
        ManStatus = 4        // { a man is hanging from the copter }
        GoodJumps = 0        // { # of successfull jumps }
        WagonSpeed = 1       // { Slowest, wagon will move 1 pixel per loop }
        Gravity = 4          // { fastest, man drops 4 pixels per loop }
        CurrentLevel = 1     // { keeps count of levels...}

        for i in 1...5 {     // { erase the thumbs...}
            EraseRect(ThumbUp[i])
            EraseRect(ThumbDown[i])
            ThumbState[i] = 0   // {none are drawn, keep track for 'update' drawing}
        }

        // {cloudstuff}
        CloudNdx = 3         // {Which cloud is being drawn?}
        StartNewCloud()      // {set up a cloud on right side and get all the regions ready}
    }

    func TakeCareControls(_ whichControl: Control) {
        if whichControl === BeginButton {   // {BEGIN a game}
            messageMenuShown = true           // {InsertMenu(myMenus[4],0)}
            menusEnabled = false              // {DisableItem(myMenus[i],0)}
            DrawMenuBar()                     // {display exit message}
            HideControl(BeginButton)
            InitialCopterStuff()              // {Reset game varibles to beginning}
            DrawScoreIntoBox(Score, ScoreNum) // {overwrite previous score,zero}
            DrawWagonStatus()                 // { into Scorebox }
            InitialSoundRates()               // {reset pitch of flipsounds}
            InvertRect(ScoreMan[1])           // {hilite first man in scorebox}
            GameUnderWay = true               // { animation loop branch is active}
            CloudOnDisplay = true             // {flag for Update, will draw in cloud}
            EraseRect(FlightRect)             // { Clear the Screen....}
            host?.hideCursor()                // {game mode,no normal mouse functions}
            FlushMouseDowns()                 // {clear mousedowns}
            Mask = 4                          // { mask shapes to flightRect }
            WagonMoving = true
        }
        if whichControl === ResumeButton {   // {RESUME}
            messageMenuShown = true           // {display exit message}
            menusEnabled = false
            DrawMenuBar()

            HideControl(ResumeButton)
            HideControl(EndButton)

            // {now hilite the proper man in the scorebox, was unhilited
            // when the user paused the game.}
            if MenLeft > 0 { InvertRect(ScoreMan[6 - MenLeft]) }

            GameUnderWay = true               // {we're back into game mode}
            host?.hideCursor()
            Mask = 4                          // {entire flight area}
            CopyRgn(tempRgn, CopterRgn)       // {restore prior region saved in PauseThisGame}
            FlushMouseDowns()                 // {clear all mouseDowns}
        }
        if whichControl === EndButton {   // {END current game...}
            if LevelOnDisplay {   // {Hide levelbutton if it's drawn}
                LevelOnDisplay = false
                HideControl(LevelButton)
                UnionRgn(CopterRgn, LevelUnion, CopterRgn)   // {restore button area to CopterRgn}
            }
            HideControl(ResumeButton)   // {hide the resume and end}
            HideControl(EndButton)
            InvalRect(FlightRect)       // {make 'Update' redraw the begin screen}
            for i in 1...2 { FillRect(FlipFrame[i], dkGray) }   // {flip showing?}
            WhichSound = 0
            ShowControl(BeginButton)
            Mask = 1                    // {mask out begin button}
            CloudOnDisplay = false
            CopyRgn(FlightRgn[Mask], CopterRgn)   // {must use CopyRgn instead of ':='}
        }
    }

    func PauseThisGame() {   // {called if a backspace or doubleclick during game}
        GameUnderWay = false          // { halt animation }
        FillRect(YokeErase, gray)     // { Cover the yoke }
        if MenLeft > 0 { InvertRect(ScoreMan[6 - MenLeft]) }   // {unhilite man in scorebox}
        host?.showCursor()
        ShowControl(ResumeButton)
        ShowControl(EndButton)
        messageMenuShown = false      // {remove exit message,i-354}
        menusEnabled = true           // {show other menu options}
        DrawMenuBar()
        Mask = 3                      // { flags a pause is underway....mask out buttons}
        CopyRgn(CopterRgn, tempRgn)   // {keep old region in case we resume this game}
        DiffRgn(FlightRgn[Mask], CloudRgn[CloudNdx], CopterRgn)   // {Mask Cloud from region}
        PBKillIO()                    // {kill any current sound}
    }

    /// Modern addition: pause when the app loses focus.
    public func pauseIfPlaying() {
        if GameUnderWay { PauseThisGame() }
    }

    func TakeCareMouseDown(_ where_: Point) {
        if GameUnderWay {   // {game is underway..Mousedown can only drop man}
            if ManStatus == 4 {   // {man is hanging so begin the drop}
                ManNdx = 2   // { draw first man dropping at current manRect}
                CopyBits(OffScreen, myWindow.portBits, OffMan[ManNdx], ManRect, srcCopy, CopterRgn)
                ManStatus = 0   // {this flags that a man is now dropping}
                HeightOfDrop = WagonRect.bottom - CoptRect.bottom   // {for score}
            }
        } else {   // { then Mouse is normal...handle normal functions }
            // {inContent: by not selecting the window, DA's can be open during game}
            if let c = FindControl(where_) {
                trackingControl = c   // {TrackControl: finishes on mouseUp}
                HiliteControl(c, 1)
            }
        }
    }

    func FindControl(_ pt: Point) -> Control? {
        [BeginButton, ResumeButton, EndButton, LevelButton].first {
            $0!.contrlVis && $0!.contrlHilite != 255 && $0!.contrlRect.contains(pt)
        } ?? nil
    }

    func TakeCareKeyDown(_ CharCode: Character) {
        // {command keys arrive as menu commands from the host}
        if (CharCode == BackSpace || CharCode == Escape) && GameUnderWay { PauseThisGame() }
    }

    func OneTimeGameStuff() {   // {set up the gamestuff only needed on startup}
        CloudOnDisplay = false   // {no clouds are to be drawn by update}
        // { center ScoreBoxRect in Window bottom }
        OffsetRect(&ScoreBoxRect, -ScoreBoxRect.left, myWindow.portRect.bottom - ScoreBoxRect.bottom)
        let i = (myWindow.portRect.right - ScoreBoxRect.right) / 2
        OffsetRect(&ScoreBoxRect, i, -2)
        OffsetRect(&WagonRect, -WagonRect.left, ScoreBoxRect.top - 4 - WagonRect.bottom)   // {wagon to baseline}
        OffsetRect(&CoptRect, 0, WagonRect.top - 10 - CoptRect.bottom)   // {lowest copter}
        CopterBottomLimit = CoptRect.bottom   // {lower limit for copterflight}
        SetRect(&BorderRect, -76, -4, 509, CoptRect.top - 1)

        // {we'll let Update draw the scorebox over a gray background}

        // {now define the flight area and various masking regions}
        FlightRect = myWindow.portRect
        FlightRect.bottom = ScoreBoxRect.top - 4   // {define flight area}
        RectRgn(FlightRgn[4], FlightRect)
        DiffRgn(FlightRgn[4], BeginRgn, FlightRgn[1])   // { Flight less begin button }
        DiffRgn(FlightRgn[4], EndRgn, FlightRgn[2])     // { Flight less End button}
        DiffRgn(FlightRgn[1], EndRgn, FlightRgn[3])     // {Flight less both buttons}
        DisposeRgn(BeginRgn)

        // {now locate two fliprect's on either side of scoreBox }
        do {
            let pr = myWindow.portRect
            var width = ScoreBoxRect.left - pr.left   // {width of area}
            let dh = (width - (FlipRect[1].right - FlipRect[1].left)) / 2
            width = pr.bottom - ScoreBoxRect.top + 4  // {height of area}
            let dv = (width - (FlipRect[1].bottom - FlipRect[1].top)) / 2
            // {Left flip location, destination-source}
            OffsetRect(&FlipRect[1], pr.left + dh - FlipRect[1].left, pr.bottom - dv - FlipRect[1].bottom)
            // {Right flip location, destination-source}
            OffsetRect(&FlipRect[2], ScoreBoxRect.right + dh - FlipRect[2].left, pr.bottom - dv - FlipRect[2].bottom)
        }

        for i in 1...2 {   // { Frames for flips....}
            var tRect = FlipRect[i]
            InsetRect(&tRect, -4, -4)          // {give the guy some room to flip}
            tRect.bottom = tRect.bottom - 3    // {but keep his feet on the ground}
            FlipFrame[i] = tRect
        }

        // {establish Crosshair control limits}
        YokeLimits = ScoreBoxRect
        YokeLimits.right = YokeLimits.left + 51
        YokeErase = YokeLimits
        InsetRect(&YokeLimits, 7, 7)   // {limits of movement of center of cross}
        InsetRect(&YokeErase, 4, 4)    // {used to create MaskRgn,mask copyBits for cross}

        // {using MaskRgn forces CopyBits to draw only the visible part of the cross
        // into the ScoreBox, making it appear to slide inside the box}
        MaskRgn = NewRgn()
        RectRgn(MaskRgn, YokeErase)    // {OpenRgn; FrameRect(YokeErase); CloseRgn(MaskRgn)}

        // {now locate Cross centerline relative to Yoke window.topleft, each loop the
        // destination rectangle for the drawing the Cross is offset from this
        // position... the offset is determined by mapping the mouse position into
        // the MouseRect in the AnimateOneLoop procedure}
        var Dest = Point.zero
        Dest.h = YokeLimits.left - ((CrossRect.right - CrossRect.left) / 2)
        Dest.v = YokeLimits.top - ((CrossRect.bottom - CrossRect.top) / 2)
        OffsetRect(&CrossRect, Dest.h - CrossRect.left, Dest.v - CrossRect.top)

        SetRect(&MouseRect, 210, 134, 302, 206)   // { this is for mapping control }
        SetRect(&DeltaRect, -4, -3, 4, 4)         // { this is for finding copter offset }

        // {find all the Constants used to locate Cross in ScoreBox, we'll be
        // replacing MapPt and OffSetRect calls}
        YokeHt = YokeLimits.bottom - YokeLimits.top
        YokeWdth = YokeLimits.right - YokeLimits.left
        MouseHt = MouseRect.bottom - MouseRect.top
        MouseWdth = MouseRect.right - MouseRect.left
        OffsetHt = YokeLimits.top - CrossRect.top
        OffsetWdth = YokeLimits.left - CrossRect.left
        CrossHt = CrossRect.bottom - CrossRect.top
        CrossWdth = CrossRect.right - CrossRect.left
        DeltaHt = DeltaRect.bottom - DeltaRect.top
        DeltaWdth = DeltaRect.right - DeltaRect.left

        // { onscreen rectangles based in ScoreBox }
        var tRect = OffMan[1]   // {size of man..locate ScoreMan in ScoreBox}
        OffsetRect(&tRect, ScoreBoxRect.left + 54 - tRect.left, ScoreBoxRect.top - tRect.top)
        for i in 1...5 {
            ScoreMan[i] = tRect      // { boxes to track which man is in action}
            OffsetRect(&tRect, 0, 17)    // { move one row down }
            ThumbUp[i] = tRect       // { boxes for thumbs up }
            OffsetRect(&tRect, 0, 17)
            ThumbDown[i] = tRect     // { Boxes for thumbs down }
            OffsetRect(&tRect, 15, -34)  // { back to top and over one}
            ThumbState[i] = 0        // {No Thumbs are drawn yet}
        }

        tRect = OffNum[1]   // {size of Numbers..locate in ScoreBox}
        OffsetRect(&tRect, ScoreBoxRect.left + 135 - tRect.left, ScoreBoxRect.top + 10 - tRect.top)
        for i in 1...6 {
            ScoreNum[i] = tRect      // { boxes to record score digits}
            OffsetRect(&tRect, 0, 25)    // { move one row down }
            HiScoreNum[i] = tRect    // { boxes for hiscore digits }
            OffsetRect(&tRect, 21, -25)
        }

        // {find point for writing current height into the scorebox}
        // {HtStatRect is destination rect in scorebox, Offheight is source rect
        //  in OffScreen, HeightPt is moveto location in offScreen}
        HeightStr = "444"   // {max width for 3 numerals?,for centering in box}
        HtStatRect.top = ScoreBoxRect.top + 2
        HtStatRect.left = ScoreBoxRect.right - 48
        HtStatRect.bottom = ScoreBoxRect.top + 14
        HtStatRect.right = HtStatRect.left + StringWidth(HeightStr)
        OffHeight = HtStatRect   // {offScreen rect to contain drawstring}
        OffsetRect(&OffHeight, OffHorse.right - OffHeight.left, OffHorse.bottom - OffHeight.bottom)   // {right of dead horse}
        HeightPt.h = OffHeight.left
        HeightPt.v = OffHeight.bottom   // {'moveto' location for height in offscreen}

        OldBits = myWindow.portBits   // {always preserve the old map!!}
        SetPortBits(OffScreen)
        FillRect(OffHeight, white)    // {erase to white}
        SetPortBits(OldBits)          // {restore old bitmap}

        tRect = HtStatRect
        InsetRect(&tRect, -14, -1)
        OffsetRect(&tRect, 0, 17)     // {size and locate Rects for Wagon/gravity}
        WagStatRect = tRect
        OffsetRect(&tRect, 0, 17)
        GravStatRect = tRect

        WagonStatus[1] = "WALK"
        WagonStatus[2] = "TROT"
        WagonStatus[3] = "GALLOP"
        GravityStatus[4] = "HEAVY"    // {strings for Wagon speed and gravity}
        GravityStatus[3] = "NORMAL"
        GravityStatus[2] = "OH BOY"
        GravityStatus[1] = "FLYING"
    }

    func AnimateWagonCopter(_ ClipTo: Region, _ DrawWagon: Bool) {
        // {animate copter/wagon while game is not underway}
        if CoptNdx < 3 { CoptNdx += 1 } else { CoptNdx = 1 }
        OffsetRect(&CoptRect, 212 - CoptRect.left, 110 - CoptRect.top)
        CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, ClipTo)
        if DrawWagon {
            if WagonNdx < 3 { WagonNdx += 1 } else { WagonNdx = 1 }
            if WagonRect.left > 510 { OffsetRect(&WagonRect, -WagonRect.right, 0) }
            else { OffsetRect(&WagonRect, WagonSpeed, 0) }
            CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)
        }
        // {draw current height into scorebox}
        Height = WagonRect.bottom - CoptRect.bottom
        HeightStr = String(Height)
        OldBits = myWindow.portBits
        SetPortBits(OffScreen)            // {we want to draw into offScreen}
        EraseRect(OffHeight)              // {erase to white}
        MoveTo(HeightPt.h, HeightPt.v)    // {move the pen to bottom left of OffHeight}
        DrawString(HeightStr)             // { draw current height into offscreen}
        SetPortBits(OldBits)              // {restore old bitmap}
        CopyBits(OffScreen, myWindow.portBits, OffHeight, HtStatRect, srcCopy, nil)   // {now stamp it onto the screen}
    }

    func ResetManHanging() {   // {test for end of game, reset if more men available}
        // { the following executed success or fail }
        ManStatus = 4   // {man is hanging}
        InvertRect(ScoreMan[6 - MenLeft])   // { make last scorebox man normal}
        MenLeft -= 1
        if MenLeft > 0 { InvertRect(ScoreMan[6 - MenLeft]) }   // {next man}
        OffsetRect(&ManRect, CoptRect.left + 36 - ManRect.left, CoptRect.top + 23 - ManRect.top)   // {move ManRect back up to Copter}
        if MenLeft == 0 {   // { *** end of this level...}
            if GoodJumps < 5 {   // { ****  end of this game }
                GameUnderWay = false
                if Score > HiScore {   // {New HiScore?}
                    HiScore = Score
                    DrawScoreIntoBox(HiScore, HiScoreNum)
                }
                host?.showCursor()
                PBKillIO()   // {kill sound}
                WhichSound = 0
                EraseRect(CoptRect)             // {erase last copter}
                EraseRect(Cloud[CloudNdx])      // {erase last cloud}
                CloudOnDisplay = false          // {no cloud for Update}
                FillRect(YokeErase, gray)       // { fill in yoke }
                messageMenuShown = false        // { remove exit message,i-354}
                menusEnabled = true
                DrawMenuBar()
                ShowControl(BeginButton)
                Mask = 1
                DrawAllmyStrings()
            } else {   // { move on to next level stuff}
                Mask = 2   // { mask out level button }
                CurrentLevel += 1   // { next level }
                LevelToButtonTitle(CurrentLevel)   // {level to buttontitle}
                ShowControl(LevelButton)
                LevelOnDisplay = true
                DiffRgn(CopterRgn, EndRgn, CopterRgn)   // {mask levelbutton from CopterRgn}
                LevelTimer = TickCount() + 120   // {time levelbutton onscreen 2 secs.}
                if WagonSpeed == 3 && Gravity > 1 { Gravity = Gravity - 1 }   // {MaxGravity = 4}
                if WagonSpeed < 3 { WagonSpeed = WagonSpeed + 1 }
                DrawWagonStatus()   // {update scorebox for wagon/gravity}
                MenLeft = 5         // { # of men/level }
                InvertRect(ScoreMan[1])
                GoodJumps = 0       // { # of successfull jumps }
                for i in 1...5 {    // {erase the last set of thumbs...}
                    EraseRect(ThumbUp[i])
                    EraseRect(ThumbDown[i])
                    ThumbState[i] = 0
                }
                if CurrentLevel < 6 {   // { higher pitch flipsound }
                    for i in 1...4 {
                        for v in 0..<4 { FlipSound[i].rates[v] = 2 * FlipSound[i].rates[v] }   // {raise pitch one octave}
                    }
                }
            }
        }
        FlushMouseDowns()   // {so an old mousedown will not drop new man!}
    }

    func AnimateOneLoop() {
        var MouseLoc = host?.getMouse() ?? Point(h: 256, v: 170)   // { MouseLoc in Coords of currentGrafPort }

        // {if out of bounds then limit MouseLoc to MouseRect extremes }
        if MouseLoc.h > MouseRect.right { MouseLoc.h = MouseRect.right }
        else if MouseLoc.h < MouseRect.left { MouseLoc.h = MouseRect.left }

        if MouseLoc.v > MouseRect.bottom { MouseLoc.v = MouseRect.bottom }
        else if MouseLoc.v < MouseRect.top { MouseLoc.v = MouseRect.top }

        switch CoptNdx {
        // {split time between clouds,height and cross...draw each every 3rd loop}
        case 1:   // {height into scorebox, use offscreen to avoid flicker}
            HeightStr = String(WagonRect.bottom - CoptRect.bottom)
            OldBits = myWindow.portBits
            SetPortBits(OffScreen)            // {we want to draw into offScreen}
            EraseRect(OffHeight)              // {erase to white}
            MoveTo(HeightPt.h, HeightPt.v)    // {move the pen to bottom left of OffHeight}
            DrawString(HeightStr)             // { draw current height into offscreen}
            SetPortBits(OldBits)              // {restore old bitmap}
            CopyBits(OffScreen, myWindow.portBits, OffHeight, HtStatRect, srcCopy, nil)   // {now stamp it onto the screen}
            CoptNdx += 1

        case 2:   // {cloudstuff}
            if Cloud[CloudNdx].right < 0 { StartNewCloud() }   // {is it offscreen left?}
            Cloud[CloudNdx].left -= 1
            Cloud[CloudNdx].right -= 1   // {move cloudrect left,faster than OffsetRect}
            OffsetRgn(CloudRgn[CloudNdx], -1, 0)   // {move the masking region too}

            // {draw the cloud masked by the cloudrgn}
            CopyBits(OffScreen, myWindow.portBits, OffCloud[CloudNdx], Cloud[CloudNdx], srcCopy, CloudRgn[CloudNdx])

            // {move the CopterRgn to mask the new cloud position}
            OffsetRgn(CopterRgn, -1, 0)
            CoptNdx += 1   // {next Copter shape}

            // {level stuff is here because we are masking the button onto CopterRgn}
            if LevelOnDisplay {   // { is level button being shown?}
                if TickCount() > LevelTimer {   // {put away levelbutton if time is up}
                    Mask = 4   // { normal window}
                    UnionRgn(CopterRgn, LevelUnion, CopterRgn)   // {put back last level mask}
                    HideControl(LevelButton)
                    LevelOnDisplay = false
                } else {   // {make sure level is masked properly as copterRgn scrolls}
                    UnionRgn(CopterRgn, LevelUnion, CopterRgn)   // {put back last mask}
                    DiffRgn(CopterRgn, EndRgn, CopterRgn)        // {mask out present}
                }
            }

        case 3:
            // {Draw CrossHair into ScoreBox,use tpoint to preserve MouseLoc}
            // {lets do our own MapPt and Offset calculations here instead of ROM calls}
            var tRect = Rect.zero
            tRect.left = CrossRect.left + YokeWdth * (MouseLoc.h - 210) / 92
            tRect.right = tRect.left + CrossWdth
            tRect.top = CrossRect.top + YokeHt * (MouseLoc.v - 134) / 72
            tRect.bottom = tRect.top + CrossHt
            CopyBits(OffScreen, myWindow.portBits, OffCross, tRect, srcCopy, MaskRgn)
            CoptNdx = 1

        default:
            break
        }

        // {find distance to move the copter for this loop}
        // {MapPt will convert our MouseLoc into a point in the DeltaRect which
        // represents what the user is requesting for the copter move in pixels per
        // loop, since objects cannot instantly accelerate, we will accelerate one
        // pixel of offset per loop.}
        MapPt(&MouseLoc, MouseRect, DeltaRect)

        if MouseLoc.h > Dh { Dh += 1 }   // {MouseLoc.h won't be over 4 or under -4}
        else if MouseLoc.h < Dh { Dh -= 1 }
        if MouseLoc.v > Dv { Dv += 1 }
        else if MouseLoc.v < Dv { Dv -= 1 }   // {Dh,Dv are offset to move copter}

        CoptRect.left = CoptRect.left + Dh   // {faster than an OffsetRect}
        CoptRect.right = CoptRect.right + Dh
        CoptRect.top = CoptRect.top + Dv
        CoptRect.bottom = CoptRect.bottom + Dv

        // {now check location,BorderRect sets limits for Copter at edges of window}
        if !PtInRect(CoptRect.topLeft, BorderRect) {   // {outside,find which}
            if CoptRect.left > 510 { OffsetRect(&CoptRect, -CoptRect.right, 0) }   // {wraparound}
            if CoptRect.left < -76 { OffsetRect(&CoptRect, 510 - CoptRect.left, 0) }   // {wrap}
            if CoptRect.top < -4 { OffsetRect(&CoptRect, 0, -4 - CoptRect.top) }
            if CoptRect.bottom > CopterBottomLimit {
                OffsetRect(&CoptRect, 0, CopterBottomLimit - CoptRect.bottom)
            }
        }

        if WagonNdx < 3 { WagonNdx += 1 } else { WagonNdx = 1 }   // {which wagon shape}
        if WagonRect.left > 512 {
            OffsetRect(&WagonRect, -582, 0)
        } else {
            WagonRect.left = WagonRect.left + WagonSpeed   // {locate next wagon}
            WagonRect.right = WagonRect.right + WagonSpeed
        }

        switch ManStatus {
        case 0:   // { man is dropping......}
            if ManRect.bottom > WagonRect.top {   // {Check for a hit!}
                CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)   // {draw copter}
                EraseRect(ManRect)   // { erase man and redraw wagon}
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)

                let Where = ManRect.left - WagonRect.left   // {where relative to wagon}
                let Which: Int
                if Where < -6 || Where > 70 { Which = 0 }   // {no hit}
                else if Where < 34 { Which = 1 }            // {success }
                else if Where < 45 { Which = 2 }            // {hit driver}
                else { Which = 3 }                          // {hit horse!}
                switch Which {
                case 1:   // {landed in hay so initialize Success}
                    CopyBits(OffScreen, myWindow.portBits, OffMan[7], ThumbUp[6 - MenLeft], srcCopy, nil)   // {draw Thumbs UP!}
                    ThumbState[6 - MenLeft] = 1
                    Score = Score + CurrentLevel * HeightOfDrop
                    DrawScoreIntoBox(Score, ScoreNum)
                    if Score > HiScore {   // {New HiScore?}
                        HiScore = Score
                        DrawScoreIntoBox(HiScore, HiScoreNum)
                    }
                    for i in 1...2 {
                        EraseRect(FlipFrame[i])   // {erase area for the flips}
                        FrameRect(FlipFrame[i])   // {frame for Flips}
                    }
                    GoodJumps += 1
                    ManStatus = 1   // {flag its a success!}
                    FlipCount = 3   // {index for the flips}
                    if SoundOn {    // {start the first of four flipsounds}
                        PBKillIO()   // {kill sound}
                        WhichSound = 1
                        // {store flipsound stuff into SoundParmBlk}
                        SoundParmBlk = (.flipSynth, 6)
                        FlipSynthSndRec = WhichSound
                        // {reset duration always..as it is altered by Driver}
                        for j in 1...4 { FlipSound[j].duration = FlipTime[j] }
                        PBWrite()   // {do the Flip sound}
                    }
                default:   // { 0,2,3: missed the hay.... initialize Splat}
                    CopyBits(OffScreen, myWindow.portBits, OffMan[14], ThumbDown[6 - MenLeft], srcCopy, nil)   // {Thumbs down}
                    ThumbState[6 - MenLeft] = 2   // {remember thumbstate for update}
                    FlipCount = 16   // {index for drawing flip/splat shapes}
                    if SoundOn {
                        PBKillIO()
                        WhichSound = 0   // {restart copter sound after splat}
                        SoundParmBlk = (.splat, SplatBuff)
                        PBWrite()   // {do the splatsound}
                    }
                    OffsetRect(&ManRect, 0, WagonRect.bottom - 13 - ManRect.bottom)
                    switch Which {   // {determine which kind of failure}
                    case 0:   // {missed the whole thing!}
                        ManStatus = 2   // {its a failure}
                        OffsetRect(&ManRect, 0, WagonRect.bottom - ManRect.bottom)
                    case 2: ManStatus = 8   // {hit the driver}
                    case 3: ManStatus = 9   // {hit the horse}
                    default: break
                    }
                }
            } else {   // {man is dropping but not down to wagon yet..keep going}
                if ManNdx < 6 { ManNdx += 1 } else { ManNdx = 2 }   // {next man}
                // {how about some effects on man dropping thru cloud!!}
                if PtInRgn(ManRect.topLeft, CloudRgn[CloudNdx]) {
                    OffsetRect(&ManRect, Random() / 10924, 1)   // {drop is 1 pixel}
                } else {   // {man not behind cloud so normal drop}
                    ManRect.top = ManRect.top + Gravity   // {locate next man}
                    ManRect.bottom = ManRect.bottom + Gravity
                }
                CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)
                CopyBits(OffScreen, myWindow.portBits, OffMan[ManNdx], ManRect, srcCopy, CopterRgn)
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)
            }

        case 1:   // {Success is underway... flips and man in wagon}
            CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)   // {draw the copter}
            if FlipCount < 46 {   // {for 1 to 15 shapes every third loop}
                if FlipCount % 3 == 0 {   // {Draw every 3rd time thru}
                    let i = FlipCount / 3
                    CopyBits(OffScreen, myWindow.portBits, OffFlip[i], FlipRect[1], srcCopy, nil)   // {Draw left flip}
                    CopyBits(OffScreen, myWindow.portBits, OffFlip[i], FlipRect[2], srcCopy, nil)
                }
                OffsetRect(&ManInWagon, WagonRect.left - ManInWagon.left, WagonRect.top - ManInWagon.top)
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)   // {draw wagon}
                CopyBits(OffScreen, myWindow.portBits, OffManInWagon, ManInWagon, srcCopy, nil)   // {draw Man in Wagon}
                FlipCount += 1
            } else {   // {the flip is complete...get ready for the next man}
                for i in 1...2 { FillRect(FlipFrame[i], dkGray) }   // {Erase last flip}
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)   // {draw wagon}
                ResetManHanging()   // { set up another man/level or end}
            }

        case 2, 8, 9:   // {Fail is underway... drawing splat shapes}
            CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)
            if FlipCount < 27 {   // {for 8 to 13 shapes}
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)   // {draw wagon}
                if FlipCount % 2 == 0 {   // {Draw every other time thru}
                    CopyBits(OffScreen, myWindow.portBits, OffMan[FlipCount / 2], ManRect, srcCopy, nil)
                }
                FlipCount += 1
            } else {   // {Splat animation is complete...finish up}
                EraseRect(ManRect)
                CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)   // {draw wagon}
                switch ManStatus {
                case 8:   // {hit the driver}
                    OffsetRect(&DriverRect, WagonRect.right - DriverRect.right, WagonRect.top - DriverRect.top)
                    CopyBits(OffScreen, myWindow.portBits, OffDriver, DriverRect, srcCopy, nil)   // {draw dead driver}
                    InvertRect(ScoreMan[6 - MenLeft])
                    MenLeft = 1   // {this will end the game}
                    InvertRect(ScoreMan[6 - MenLeft])
                    WagonMoving = false   // {leave the last wagon as is}
                case 9:   // {hit the horse}
                    OffsetRect(&HorseRect, WagonRect.right - HorseRect.right, WagonRect.top - HorseRect.top)
                    CopyBits(OffScreen, myWindow.portBits, OffHorse, HorseRect, srcCopy, nil)   // {draw dead horse}
                    InvertRect(ScoreMan[6 - MenLeft])
                    MenLeft = 1   // {end the game}
                    InvertRect(ScoreMan[6 - MenLeft])
                    WagonMoving = false
                default:
                    break
                }
                ResetManHanging()
            }

        case 4:   // {ManHanging on to copter}
            // { Draw Man and Wagon and continue...waiting for mousedown}
            ManRect.left = CoptRect.left + 36
            ManRect.right = ManRect.left + ManWdth
            ManRect.top = CoptRect.top + 23
            ManRect.bottom = ManRect.top + ManHt   // {locate man relative to copter}
            CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)
            CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)
            CopyBits(OffScreen, myWindow.portBits, OffMan[1], ManRect, srcCopy, CopterRgn)

        default:
            break
        }
        // {If SpeedTrapOn then Delay(SpeedFactor,SpeedTick) — see speedMultiplier}
    }

    func DrawUpDateStuff() {
        // {will draw all our images in response to Update event,an Update event is
        // waiting for our newly opened window so will draw our first stuff too!}

        // { draw in the scorebox over gray background }
        var tRect = myWindow.portRect; tRect.top = ScoreBoxRect.top - 3
        FillRect(tRect, dkGray)
        CopyBits(OffScreen, myWindow.portBits, OffScoreBox, ScoreBoxRect, srcCopy, nil)
        MoveTo(0, ScoreBoxRect.top - 4)
        LineTo(512, ScoreBoxRect.top - 4)   // {wagon Baseline or 'ground'line}

        CopyBits(OffScreen, myWindow.portBits, OffWagon[WagonNdx], WagonRect, srcCopy, nil)   // {draw the wagon}

        // {  Draw Thumbs into ScoreBox }
        for i in 1...5 {
            switch ThumbState[i] {   // {ThumbState determines which thumb to draw if any}
            case 1: CopyBits(OffScreen, myWindow.portBits, OffMan[7], ThumbUp[i], srcCopy, nil)   // {Thumbs UP! in upper box}
            case 2: CopyBits(OffScreen, myWindow.portBits, OffMan[14], ThumbDown[i], srcCopy, nil)   // {Thumbs down in lower box}
            default: break
            }
        }

        DrawScoreIntoBox(Score, ScoreNum)   // { Draw Scores into ScoreBox }
        DrawScoreIntoBox(HiScore, HiScoreNum)

        DrawWagonStatus()   // { Draw Wagon and Gravity info}

        // {Invert proper man in scorebox, don't think this is ever used}
        if MenLeft > 0 && GameUnderWay { InvertRect(ScoreMan[6 - MenLeft]) }

        for i in 1...2 { FillRect(FlipFrame[i], dkGray) }
        FillRect(YokeErase, gray)   // { cover the yoke until resume or newgame}

        if Mask == 1 {   // {this is used on start up or waiting for begin}
            DrawAllmyStrings()
            ShowControl(BeginButton)
        }
        // {draw cloud if one is showing}
        if CloudOnDisplay {
            CopyBits(OffScreen, myWindow.portBits, OffCloud[CloudNdx], Cloud[CloudNdx], srcCopy, CloudRgn[CloudNdx])
        }
    }

    func TakeCareUpdates() {
        let TempPort = GetPort()
        SetPort(myWindow)
        // {BeginUpDate: visRgn is restricted to the update region}
        let savedVis = myWindow.visRgn
        let vis = Region(rect: myWindow.portRect)
        SectRgn(vis, myWindow.updateRgn, vis)
        myWindow.visRgn = vis
        myWindow.updateRgn.setEmpty()
        EraseRect(myWindow.portRect)
        DrawUpDateStuff()
        DrawControls()
        myWindow.visRgn = savedVis   // {EndUpDate}
        SetPort(TempPort)
    }

    func DrawControls() {
        for c in [BeginButton, ResumeButton, EndButton, LevelButton] { Draw1Control(c!) }
    }

    func CloseStuff() {
        PBKillIO()   // {always kill sound i/o before quitting!}
    }

    func FlushMouseDowns() {
        eventQueue.removeAll { if case .mouseDown = $0 { return true } else { return false } }
    }

    // MARK: - Main program

    /// The BEGIN…END of the Pascal main program, minus MainEventLoop.
    public func start() throws {
        // {InitThings: InitGraf, fonts, windows, menus... handled by the host}
        SoundOn = true   // {sound will start on first begin}
        host?.checkSoundItem(SoundOn)
        CreateRegions()
        CreateWindow()             // {load window,dialogs,controls}
        CreateSound()              // {set up sound buffers, Apple tech note 19}
        CreateOffScreenBitMap()    // {see Apple tech note 41}
        try CreatePictures()       // {load pictures from resources}
        DrawPicsIntoOffScreen()
        CreateStrings()            // {load strings from resources}
        CreateOffScreenRects()     // {set all rectangles for 'copybits' shape drawing}
        DrawCloudsIntoOffScreen()  // {depends on OffScreenRects being defined}
        OneTimeGameStuff()         // {Game varibles, scorebox stuff,etc}
        HiScore = host?.savedHiScore() ?? 0   // {was HiScore := 0}
        InitialCopterStuff()       // {called at start of each game,begin button}
        GameUnderWay = false
        Mask = 1                   // { FlightRgn[1] }
        // {first Update event will draw everything in our game window }
        EraseRect(myWindow.portRect)
        InvalRect(myWindow.portRect)
        DrawMenuBar()
    }

    // MARK: - Event loop

    public func post(_ event: GameEvent) { eventQueue.append(event) }

    /// One pass of MainEventLoop: handle pending events, then (if nothing needed
    /// the loop's attention) run one animation step.
    public func tick() {
        guard !Finished else { return }
        while !eventQueue.isEmpty {
            let ev = eventQueue.removeFirst()
            switch ev {
            case .mouseDown(let p): TakeCareMouseDown(p)
            case .mouseDragged(let p):
                if let c = trackingControl { HiliteControl(c, c.contrlRect.contains(p) ? 1 : 0) }
            case .mouseUp(let p):
                if let c = trackingControl {
                    trackingControl = nil
                    HiliteControl(c, 0)
                    if c.contrlRect.contains(p) { TakeCareControls(c) }
                }
            case .keyDown(let ch): TakeCareKeyDown(ch)
            }
        }
        if !myWindow.updateRgn.isEmpty {
            TakeCareUpdates()
            return
        }
        if trackingControl != nil { return }   // {TrackControl owns the loop}
        idle()
    }

    func idle() {   // {no event pending so lets do some game stuff}
        if GameUnderWay {
            AnimateOneLoop()   // {draw all our shapes}

            // {sound stuff... ioresult will be <1 if sound is finished}
            if soundDriver.isDone {   // {only if sound is done}
                if GameUnderWay && SoundOn {   // {animate loop might end game}
                    switch WhichSound {
                    case 0:   // {reset copterSound}
                        SoundParmBlk = (.copt, CoptBuff)
                    case 1, 2, 3:   // {reset next flipsound}
                        WhichSound += 1
                        FlipSynthSndRec = WhichSound
                    case 4:   // {reset last flipsound}
                        WhichSound = 0
                        FlipSynthSndRec = 4
                    default:
                        break
                    }
                    PBWrite()   // {start the sound}
                }
            }
        } else {   // {game is not underway..waiting for a begin or resume}
            switch Mask {
            case 1:   // { animate during Wait for Beginbutton press }
                AnimateWagonCopter(FlightRgn[Mask], WagonMoving)
            case 3:   // { animate stationary copter during wait for Resume/end }
                if CoptNdx < 3 { CoptNdx += 1 } else { CoptNdx = 1 }
                CopyBits(OffScreen, myWindow.portBits, OffCopter[CoptNdx], CoptRect, srcCopy, CopterRgn)
                if ManStatus == 4 {
                    OffsetRect(&ManRect, CoptRect.left + 36 - ManRect.left, CoptRect.top + 23 - ManRect.top)
                    CopyBits(OffScreen, myWindow.portBits, OffMan[1], ManRect, srcCopy, CopterRgn)
                }
            default:
                break
            }
        }
    }
}
