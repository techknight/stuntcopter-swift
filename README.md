# StuntCopter for modern macOS

A faithful native port of **StuntCopter 1.5** (1987) by the late **Duane Blehm**
(HomeTown Software) to current macOS on Apple silicon and Intel.

Fly the copter over the hay wagon and click to drop the stuntman. Land all five
men in the hay to advance a level. Your score is the drop height times the current level.
Don't land on the driver or the horse!

## How faithful is it?

- **The game logic is Blehm's Pascal, translated line by line.** Blehm's source is in
  `original/`. `Sources/StuntCopterCore/StuntCopterGame.swift` keeps every procedure
  name, variable, constant and comment, so the two files can be read side by side.
- **The art, regions, strings, dialogs, controls and menus come from the original
  1987 application's resource fork.** Nothing was redrawn.
- **Text uses Apple's actual Chicago 12 bitmap font**, from the System 6.0.8 System
  file. Bold and underline are applied the way QuickDraw applied them.
- **Rendering goes through a small re-implementation of 1-bit QuickDraw**
  (`Sources/ClassicToolbox`): `CopyBits` with mask regions, patterns, regions,
  controls and dialogs. The game draws into a retained 503×310 framebuffer exactly as
  it drew to the Mac screen, with no per-frame clearing and no sprite engine. The
  result is scaled up by whole pixels.
- **Sound comes from an emulation of the Mac Plus Sound Driver's free-form and
  four-tone synthesizers.** The game builds its sound buffers the way it did in 1987:
  the copter engine noise, the splat sawtooth, and the four-chord landing fanfare
  that rises an octave each level.
- **Random numbers come from QuickDraw's own generator**, seeded the same way, so the
  clouds and the engine noise follow the original sequence.

### Modern additions

- Integer scaling (View ▸ 1×–4×, ⌘1–⌘4) and full screen (⌃⌘F), letterboxed.
- The mouse is captured while playing. A virtual pointer is clamped to the old
  512×342 screen, so steering feels like the original, where the cursor stopped at
  the screen edge.
- **Esc** pauses as well as **Delete** (Backspace).
- The game pauses automatically when you switch to another app.
- The high score persists between launches. The original reset it every time.
- The 1987 program ran as fast as a Mac Plus could manage. Timed on an emulated
  Mac Plus, the original ran about **30 loops/s in play** and about **60 in the attract
  and pause loop**. The port runs a fixed-rate loop at those speeds (20% faster in
  play with sound off, per Blehm's own note). You can override the baseline:
  `defaults write com.techknight.StuntCopter LoopsPerSecond -float 40`.
  Options ▸ Set Speed's "SLOW BY 2/4" choices slow it to 80% and 65%.
- Quit is in the application menu, and desk accessories are gone.
- The app icon is the original `ICN#`, drawn black on white as the System 6 Finder
  showed it and scaled up by whole pixels onto a white rounded-square plate, clipped
  to the plate's shape. The `ICN#`'s "mask" half isn't a real silhouette, so it's
  ignored.

## Build and run

Requirements: macOS 14 or later, and Xcode (or the Command Line Tools) with Swift 6.

```sh
make run          # release build → build/StuntCopter.app, then open it
make test         # unit, gameplay and golden-image tests
make universal    # arm64 + x86_64 app
swift run StuntCopter   # run straight from SwiftPM
```

## Layout

| Path | What |
| --- | --- |
| `original/` | Blehm's `StuntCopter.pas` and `StuntCopter.R`, and the app's AppleDouble resource fork |
| `Resources/StuntCopter.rsrc` | the 1987 resource fork, extracted (`make resources`) |
| `Resources/Chicago12.FONT` | Chicago 12 from the System 6.0.8 System file |
| `Sources/ClassicToolbox` | resource manager, 1-bit QuickDraw, regions, fonts, controls, dialogs, Sound Driver |
| `Sources/StuntCopterCore` | the game: `StuntCopterGame.swift` is the port of `StuntCopter.pas` |
| `Sources/StuntCopter` | the AppKit shell: window, menus, frame pacing, mouse capture, audio |
| `Sources/rsrc-tool` | extracts, lists and dumps resources, embeds data, builds the icon |
| `Tools/` | Python helpers that need a System 6 disk image: the reference boot disk and font extraction |
| `Tests/` | Swift Testing suites; `Golden/*.pbm` are 1-bit reference frames |

## Comparing with the original

`Tools/make_reference_disk.py` builds an 800K System 6 boot floppy that starts
the original StuntCopter 1.5. To make it you need your own System 6.0.8 disk image
and the Python `machfs` package. You can boot the floppy in an emulator such as
[Snow](https://snowemu.com) with a Mac Plus ROM, to compare timing, sound and pixels:

```sh
python3 -m venv .venv && .venv/bin/pip install machfs
make reference SYSTEM_IMAGE="System Startup.img"
Snow.app/Contents/MacOS/Snow MacPlus.ROM --floppy build/reference/StuntCopter-boot.dsk
```

Two more tools help with comparisons:
- `Tools/measure_wagon.swift` times the wagon, which moves one pixel per loop,
  across a series of timestamped emulator screenshots.
- `Tools/diff_frames.swift` overlays an emulator screenshot on a port frame and
  colors the pixels that differ.
- `Tools/record_app_audio.swift` records one app's audio with ScreenCaptureKit, and
  `Tools/analyze_audio.swift` finds the tonal and silent stretches in a recording.
  Measuring the original's landing fanfare this way showed two things. The last chord
  plays only once, because the Sound Driver counts `duration` down to 0. And the notes
  are spaced 10–55 ms apart, because the four-tone synth takes half the CPU and the
  game waits a tick before each `PBWrite`.

The port's attract-mode frames match the original **pixel for pixel**. That
covers the title text and underline, the cloud, the BEGIN button, the score box,
the copter and the wagon.
`OriginalComparisonTests` checks this against a screenshot of the original.
The copter's in-game loop rate and the Sound Driver semantics (Inside Macintosh
II-227…230) were checked the same way.

## Credits and provenance

StuntCopter © 1986, 1987 Duane Blehm. The source code was sent to Pete Gamache by
John Calhoun and published in [gamache/blehm](https://github.com/gamache/blehm)
"without license or warranty". This port keeps Blehm's work intact and adds only
the modern plumbing around it. The About box still shows the 1987 text,
including the source-code offer and the Ulysses, Kansas address, as a historical
artifact.

The Chicago 12 font is Apple's. Neither the original game nor the font comes with
an explicit license, so check before redistributing binaries or making this
repository public.

*Rest in peace, Duane Blehm. Thanks for the games.*
