import Foundation

enum ShortcutKind: String, Codable, CaseIterable {
    case application, file
    var label: String { self == .application ? "App" : "Fil" }
}

struct ShortcutTarget: Codable, Equatable {
    var kind: ShortcutKind
    var path: String
    var bookmark: Data?
    var applicationBundleID: String?
}

struct ShortcutState: Codable, Equatable {
    var targets: [String: ShortcutTarget] = [:]
    subscript(_ id: UUID) -> ShortcutTarget? {
        get { targets[id.uuidString] }
        set { targets[id.uuidString] = newValue }
    }
}

enum ShortcutStorage {
    static func load(from url: URL) throws -> ShortcutState {
        guard FileManager.default.fileExists(atPath: url.path) else { return ShortcutState() }
        return try JSONDecoder().decode(ShortcutState.self, from: Data(contentsOf: url))
    }
    static func save(_ state: ShortcutState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
