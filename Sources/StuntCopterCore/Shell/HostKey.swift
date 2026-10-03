/// A key press as the platform shell reports it, before it becomes the character
/// GetNextEvent would have delivered.
public enum HostKey: Equatable, Sendable {
    case backspace
    case escape
    /// Keypad Enter.
    case enter
    case character(Character)

    /// The character the 1987 keyDown event message carried for this key: the game
    /// checks for backspace (exit play) and dialogs for Return / Enter / Esc.
    public var character: Character {
        switch self {
        case .backspace: "\u{8}"
        case .escape: "\u{1B}"
        case .enter: "\u{3}"
        case .character(let c): c
        }
    }
}
