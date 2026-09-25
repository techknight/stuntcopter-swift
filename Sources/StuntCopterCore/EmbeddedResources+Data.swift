import ClassicToolbox
import Foundation

extension EmbeddedResources {
    /// The resource fork of Duane Blehm's StuntCopter 1.5 (1987) application.
    static let stuntCopterFork: [UInt8] = [UInt8](Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!)
}

extension TextSheet {
    /// All of StuntCopter's text, pre-rendered in Chicago 12 (see TextInventory.swift).
    public static let stuntCopter: TextSheet = {
        let bytes = [UInt8](Data(base64Encoded: EmbeddedTextSheet.base64, options: .ignoreUnknownCharacters)!)
        return try! TextSheet(data: bytes)
    }()
}
