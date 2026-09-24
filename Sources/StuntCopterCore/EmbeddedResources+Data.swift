import Foundation

extension EmbeddedResources {
    /// The resource fork of Duane Blehm's StuntCopter 1.5 (1987) application.
    static let stuntCopterFork: [UInt8] = [UInt8](Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!)
}
