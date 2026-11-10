import Foundation

struct WindowCard: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var windowTitle: String
    var name: String
    var project = ""
    var paused = false
    var lastVisited: Date?
}

struct WindowFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var expanded = true
}

// Folder metadata is separate: the existing board file and window identities
// stay compatible with earlier versions, including an immediate rollback.
struct FolderState: Codable, Equatable {
    var folders: [WindowFolder] = []
    var memberships: [String: UUID] = [:]

    func folderID(for cardID: UUID) -> UUID? {
        guard let id = memberships[cardID.uuidString], folders.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    mutating func assign(_ cardID: UUID, to folderID: UUID?) {
        if let folderID, folders.contains(where: { $0.id == folderID }) { memberships[cardID.uuidString] = folderID }
        else { memberships.removeValue(forKey: cardID.uuidString) }
    }

    mutating func dissolve(_ folderID: UUID) {
        folders.removeAll { $0.id == folderID }
        memberships = memberships.filter { $0.value != folderID }
    }
}

enum FolderStorage {
    static func load(from url: URL) throws -> FolderState {
        guard FileManager.default.fileExists(atPath: url.path) else { return FolderState() }
        return try JSONDecoder().decode(FolderState.self, from: Data(contentsOf: url))
    }
    static func save(_ state: FolderState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

struct WindowSwitcherState {
    private(set) var order: [UUID] = []
    private(set) var selectedID: UUID?

    static func candidates(_ cards: [WindowCard], connected: Set<UUID>) -> [UUID] {
        cards.enumerated().filter { !$0.element.paused && connected.contains($0.element.id) }
            .sorted {
                let left = $0.element.lastVisited ?? .distantPast
                let right = $1.element.lastVisited ?? .distantPast
                return left == right ? $0.offset < $1.offset : left > right
            }.map { $0.element.id }
    }

    mutating func step(candidates: [UUID], current: UUID?, backwards: Bool) -> UUID? {
        if order.isEmpty {
            order = candidates
            // Starting with the current window gives Cmd-Tab-style quick
            // switching to the previously visited window on the first press.
            if let current, let index = order.firstIndex(of: current) {
                order.remove(at: index)
                order.insert(current, at: 0)
                selectedID = current
            }
        } else { order.removeAll { !candidates.contains($0) } }
        guard !order.isEmpty else { selectedID = nil; return nil }
        if let selectedID, let index = order.firstIndex(of: selectedID) {
            self.selectedID = order[(index + (backwards ? -1 : 1) + order.count) % order.count]
        } else { selectedID = backwards ? order.last : order.first }
        return selectedID
    }

    mutating func select(_ id: UUID) {
        if order.contains(id) { selectedID = id }
    }

    mutating func remove(_ id: UUID) {
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if selectedID == id { selectedID = order.isEmpty ? nil : order[min(index, order.count - 1)] }
    }

    mutating func reset() { order = []; selectedID = nil }
}

enum BoardNavigationItem: Hashable {
    case window(UUID)
    case folder(UUID)
    case pausedSection
}

enum BoardNavigation {
    static func rows(active: [WindowCard], paused: [WindowCard], folders: [WindowFolder],
                     state: FolderState, searching: Bool, pausedExpanded: Bool, forcedFolder: UUID? = nil) -> [BoardNavigationItem] {
        var result = active.filter { state.folderID(for: $0.id) == nil }.map { BoardNavigationItem.window($0.id) }
        for folder in folders {
            result.append(.folder(folder.id))
            if folder.expanded || searching || forcedFolder == folder.id {
                result += active.filter { state.folderID(for: $0.id) == folder.id }.map { .window($0.id) }
            }
        }
        if !paused.isEmpty {
            result.append(.pausedSection)
            if pausedExpanded { result += paused.map { .window($0.id) } }
        }
        return result
    }

    static func moved(in rows: [BoardNavigationItem], from current: BoardNavigationItem?, delta: Int) -> BoardNavigationItem? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(of: current) else { return delta < 0 ? rows.last : rows.first }
        return rows[max(0, min(rows.count - 1, index + delta))]
    }
}

enum BoardStorage {
    static func load(from url: URL) throws -> [WindowCard] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([WindowCard].self, from: Data(contentsOf: url))
    }

    static func save(_ cards: [WindowCard], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cards).write(to: url, options: .atomic)
    }

    static func matching(_ cards: [WindowCard], query: String, paused: Bool) -> [WindowCard] {
        cards.filter {
            $0.paused == paused && (query.isEmpty ||
                [$0.name, $0.appName, $0.project, $0.windowTitle].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
}

struct WindowIdentity: Equatable {
    let bundleID: String
    let title: String
}

// Reconnect only a unique title in the same application. Ambiguity stays disconnected.
func uniqueMatch(for card: WindowCard, candidates: [WindowIdentity], used: Set<Int>, pendingCards: [WindowCard] = []) -> Int? {
    // Several saved cards may have different aliases for the same original title.
    // A single surviving window is still ambiguous in that situation.
    guard pendingCards.filter({ $0.bundleID == card.bundleID && $0.windowTitle == card.windowTitle }).count <= 1 else { return nil }
    let matches = candidates.indices.filter {
        !used.contains($0) && candidates[$0].bundleID == card.bundleID && candidates[$0].title == card.windowTitle
    }
    return matches.count == 1 ? matches.first : nil
}

// Archiving is a separate mask. Original card data and folder membership stay
// intact; one atomic file write archives/restores an entire selection.
struct ArchiveState: Codable, Equatable {
    var archivedAt: [String: Date] = [:]
    func contains(_ id: UUID) -> Bool { archivedAt[id.uuidString] != nil }
}

enum ArchiveStorage {
    static func load(from url: URL) throws -> ArchiveState {
        guard FileManager.default.fileExists(atPath: url.path) else { return ArchiveState() }
        return try JSONDecoder().decode(ArchiveState.self, from: Data(contentsOf: url))
    }
    static func save(_ state: ArchiveState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

enum WindowScope: Hashable {
    case all, unfiled, folder(UUID)
    func contains(_ id: UUID, folders: FolderState) -> Bool {
        switch self {
        case .all: return true
        case .unfiled: return folders.folderID(for: id) == nil
        case .folder(let folder): return folders.folderID(for: id) == folder
        }
    }
}

struct WindowSearchEntry: Identifiable, Equatable {
    let id: UUID
    let title: String
    let appName: String
    let alias: String
    let folder: String
    let pinned: Bool
    let archived: Bool
    var displayName: String { alias.isEmpty ? (title.isEmpty ? appName : title) : alias }
}

enum WindowSearch {
    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "æ", with: "ae")
    }
    static func matches(_ entry: WindowSearchEntry, query: String) -> Bool {
        let searchable = normalized([entry.title, entry.appName, entry.alias, entry.folder].joined(separator: " "))
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { word in searchable.contains(normalized(String(word))) }
    }
    static func moved(in ids: [UUID], current: UUID?, delta: Int) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return delta < 0 ? ids.last : ids.first }
        return ids[max(0, min(ids.count - 1, index + delta))]
    }
}
