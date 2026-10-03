import Foundation

/// The saved settings, in %APPDATA%\StuntCopter\Preferences.txt as `key=value` lines.
final class Preferences {
    private var values: [String: String] = [:]
    private let path: String

    init() {
        let appData = ProcessInfo.processInfo.environment["APPDATA"] ?? NSHomeDirectory()
        let dir = appData + "\\StuntCopter"
        path = dir + "\\Preferences.txt"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                guard let eq = line.firstIndex(of: "=") else { continue }
                values[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
    }

    func integer(forKey key: String) -> Int { values[key].flatMap { Int($0) } ?? 0 }
    func double(forKey key: String) -> Double { values[key].flatMap { Double($0) } ?? 0 }

    func set(_ value: Int, forKey key: String) {
        guard values[key] != String(value) else { return }
        values[key] = String(value)
        let text = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "\r\n") + "\r\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
