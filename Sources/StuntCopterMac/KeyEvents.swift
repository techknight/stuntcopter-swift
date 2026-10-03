import AppKit
import StuntCopterCore

extension NSEvent {
    /// The key this event is to the game, or nil for a ⌘ shortcut (left to the menus)
    /// or a key with no character.
    var hostKey: HostKey? {
        if modifierFlags.contains(.command) { return nil }
        switch keyCode {
        case 51: return .backspace   // delete
        case 53: return .escape
        case 76: return .enter       // keypad Enter
        default: return characters?.first.map { .character($0) }
        }
    }
}
