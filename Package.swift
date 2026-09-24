// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StuntCopter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StuntCopter", targets: ["StuntCopter"]),
        .executable(name: "rsrc-tool", targets: ["rsrc-tool"]),
    ],
    targets: [
        // Pure-Swift re-implementation of the bits of the 1987 Toolbox the game uses:
        // resource forks, QuickDraw (1-bit), regions, text, the Sound Driver.
        .target(name: "ClassicToolbox"),
        // Line-by-line port of StuntCopter.pas on top of ClassicToolbox. No AppKit.
        .target(name: "StuntCopterCore", dependencies: ["ClassicToolbox"]),
        // AppKit shell: window, menus, input capture, audio output.
        .executableTarget(name: "StuntCopter", dependencies: ["StuntCopterCore"]),
        // Developer tool: extract/dump resources, generate embedded data and icons.
        .executableTarget(name: "rsrc-tool", dependencies: ["ClassicToolbox"]),
        .testTarget(name: "ClassicToolboxTests", dependencies: ["ClassicToolbox", "StuntCopterCore"]),
        .testTarget(name: "StuntCopterCoreTests", dependencies: ["StuntCopterCore"], exclude: ["Golden", "Original"]),
    ]
)
