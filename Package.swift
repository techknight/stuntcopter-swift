// swift-tools-version: 6.0
import PackageDescription

// Targets every platform builds: the Toolbox, the game, and their tests.
var products: [Product] = []
var targets: [Target] = [
    // Pure-Swift re-implementation of the bits of the 1987 Toolbox the game uses:
    // resource forks, QuickDraw (1-bit), regions, text, the Sound Driver.
    .target(name: "ClassicToolbox"),
    // Line-by-line port of StuntCopter.pas on top of ClassicToolbox. No AppKit.
    .target(name: "StuntCopterCore", dependencies: ["ClassicToolbox"]),
    .testTarget(name: "ClassicToolboxTests", dependencies: ["ClassicToolbox", "StuntCopterCore"]),
    .testTarget(name: "StuntCopterCoreTests", dependencies: ["StuntCopterCore"], exclude: ["Golden", "Original"]),
]

// The manifest is evaluated on the building machine, so these pick the host's app.
#if os(macOS)
products += [
    .executable(name: "StuntCopter", targets: ["StuntCopterMac"]),
    .executable(name: "rsrc-tool", targets: ["rsrc-tool"]),
]
targets += [
    // AppKit shell: window, menus, input capture, audio output.
    .executableTarget(name: "StuntCopterMac", dependencies: ["StuntCopterCore"]),
    // Developer tool: extract/dump resources, generate embedded data and icons.
    // Uses CoreGraphics and ImageIO, so it stays on macOS.
    .executableTarget(name: "rsrc-tool", dependencies: ["ClassicToolbox", "StuntCopterCore"]),
]
#elseif os(Windows)
products += [.executable(name: "StuntCopter", targets: ["StuntCopterWin"])]
targets += [
    // Win32 shell: window, menus, pointer lock, waveOut audio, dialogs, preferences.
    .executableTarget(
        name: "StuntCopterWin",
        dependencies: ["StuntCopterCore", "CStuntCopterWin"],
        // A GUI app (no console window); Swift's entry point is still `main`.
        linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])]
    ),
    // The waveOut audio pump, icon construction and a few Win32 macros, in C.
    .target(
        name: "CStuntCopterWin",
        linkerSettings: [.linkedLibrary("winmm"), .linkedLibrary("dwmapi"), .linkedLibrary("user32"), .linkedLibrary("gdi32")]
    ),
]
#endif

let package = Package(
    name: "StuntCopter",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
