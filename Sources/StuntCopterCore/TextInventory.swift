import ClassicToolbox

extension StuntCopterGame {
    /// Every piece of text StuntCopter draws, for pre-rendering into a TextSheet:
    /// strings drawn whole (with their face), and static dialog text as TextBox
    /// wraps it. Numbers (the height readout, the level) are assembled at runtime
    /// from the single digits and the Apple symbol.
    public static func textInventory(_ res: ResourceFork) throws
        -> (strings: [(String, TextStyle)], textBoxes: [(text: String, width: Int)]) {
        var strings: [(String, TextStyle)] = []
        var boxes: [(text: String, width: Int)] = []

        // DrawAllmyStrings: title (bold, underline) and byline.
        strings.append((try res.indString(256, 1), [.bold, .underline]))
        strings.append((try res.indString(256, 2), []))
        // DrawWagonStatus.
        for s in ["WALK", "TROT", "GALLOP", "HEAVY", "NORMAL", "OH BOY", "FLYING"] { strings.append((s, [])) }
        // Controls; LevelToButtonTitle builds "LEVEL " + Apple symbol + level number.
        for id in 129...132 { strings.append((try res.control(id).title, [])) }
        strings.append(("LEVEL ", []))
        strings.append(("\u{14}", []))
        // The height readout and level numbers.
        for d in 0...9 { strings.append((String(d), [])) }
        // Dialogs: button and radio titles, and wrapped static text.
        for id in [129, 130, 137, 138, 139] {
            for item in try res.itemList(try res.dialog(id).itemsID) {
                switch item.kind {
                case .button, .radioButton, .checkBox: strings.append((item.text, []))
                case .staticText: boxes.append((item.text, item.rect.width))
                default: break
                }
            }
        }
        return (strings, boxes)
    }
}
