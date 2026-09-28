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
#endif

let package = Package(
    name: "StuntCopter",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
