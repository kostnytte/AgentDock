import Foundation

@main
struct StorageTests {
    static var checks = 0
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDock-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/board.json")
        var original = WindowCard(bundleID: "test.codex", appName: "Codex", windowTitle: "Arbeid med API", name: "Ærlig navn – øving", project: "Praksis", paused: true, lastVisited: Date(timeIntervalSince1970: 1234567))
        let other = WindowCard(bundleID: "test.claude", appName: "Claude", windowTitle: "Arbeid med API", name: "Sparring")
        try expect(try BoardStorage.load(from: url).isEmpty, "A new installation starts empty")
        try BoardStorage.save([original, other], to: url)
        try expect(try BoardStorage.load(from: url) == [original, other], "Names, order, identity, pause and timestamps survive restart")
        original.name = "Endret"
        try BoardStorage.save([other, original], to: url)
        try expect(try BoardStorage.load(from: url) == [other, original], "Updating the board replaces a complete valid document")
        try expect(BoardStorage.matching([original, other], query: "praksis", paused: true) == [original], "Project search includes paused cards")
        try expect(BoardStorage.matching([original, other], query: "", paused: false) == [other], "Paused cards are excluded from active shortcuts")

        let identity = WindowIdentity(bundleID: "test.codex", title: "Arbeid med API")
        let candidates = [WindowIdentity(bundleID: "test.claude", title: "Arbeid med API"), identity]
        try expect(uniqueMatch(for: original, candidates: candidates, used: []) == 1, "Same title in another app cannot steal a card")
        try expect(uniqueMatch(for: original, candidates: [identity, identity], used: []) == nil, "Ambiguous identical windows never reconnect automatically")
        try expect(uniqueMatch(for: original, candidates: candidates, used: [1]) == nil, "A live window cannot be connected to two cards")
        try expect(uniqueMatch(for: original, candidates: [WindowIdentity(bundleID: "test.codex", title: "Another task")], used: []) == nil, "A closed card never silently switches tasks")
        var duplicate = original
        duplicate.id = UUID()
        duplicate.name = "A different task with the same window title"
        try expect(uniqueMatch(for: original, candidates: [identity], used: [], pendingCards: [original, duplicate]) == nil,
            "One remaining window cannot arbitrarily claim one of two saved cards with the same title")

        let boardBytes = try Data(contentsOf: url)
        let foldersURL = directory.appendingPathComponent("nested/folders.json")
        try expect(try FolderStorage.load(from: foldersURL) == FolderState(), "Existing users start with no folders and no migration")
        var folders = FolderState()
        let customers = WindowFolder(name: "Kunder")
        let development = WindowFolder(name: "Utvikling", expanded: false)
        folders.folders = [customers, development]
        folders.assign(original.id, to: customers.id)
        folders.assign(other.id, to: customers.id)
        try FolderStorage.save(folders, to: foldersURL)
        try expect(try FolderStorage.load(from: foldersURL) == folders, "Folder membership and collapsed state survive restart")
        try expect(try Data(contentsOf: url) == boardBytes, "Creating and filling folders never rewrites the existing board")
        try expect(folders.folderID(for: original.id) == customers.id && folders.folderID(for: other.id) == customers.id,
            "Windows from different apps can belong to the same customer folder")
        folders.assign(other.id, to: development.id)
        try expect(folders.folderID(for: other.id) == development.id && folders.folderID(for: original.id) == customers.id,
            "Moving one window does not move another")
        folders.assign(other.id, to: nil)
        try expect(folders.folderID(for: other.id) == nil, "A window can move back out of a folder")
        let beforeDissolve = folders
        folders.dissolve(customers.id)
        try expect(folders.folderID(for: original.id) == nil && !folders.folders.contains(where: { $0.id == customers.id }),
            "Dissolving a folder leaves its windows available outside folders")
        try expect(try BoardStorage.load(from: url) == [other, original], "Dissolving folders preserves window identities and pause state")
        folders = beforeDissolve
        try expect(folders.folderID(for: original.id) == customers.id, "Undo restores the folder and its membership")
        folders.memberships[other.id.uuidString] = UUID()
        try expect(folders.folderID(for: other.id) == nil, "An unknown folder cannot hide a window")

        var first = WindowCard(bundleID: "test.codex", appName: "Codex", windowTitle: "First", name: "First", lastVisited: Date(timeIntervalSince1970: 100))
        let second = WindowCard(bundleID: "test.codex", appName: "Codex", windowTitle: "Second", name: "Second", lastVisited: Date(timeIntervalSince1970: 90))
        let third = WindowCard(bundleID: "test.claude", appName: "Claude", windowTitle: "Third", name: "Third", lastVisited: Date(timeIntervalSince1970: 80))
        let paused = WindowCard(bundleID: "test.codex", appName: "Codex", windowTitle: "Paused", name: "Paused", paused: true, lastVisited: Date(timeIntervalSince1970: 200))
        let offline = WindowCard(bundleID: "test.codex", appName: "Codex", windowTitle: "Offline", name: "Offline", lastVisited: Date(timeIntervalSince1970: 300))
        let eligible = WindowSwitcherState.candidates([offline, paused, third, second, first], connected: Set([first.id, second.id, third.id, paused.id]))
        try expect(eligible == [first.id, second.id, third.id], "Switcher excludes paused and unavailable windows, ordered by last visit")
        var switcher = WindowSwitcherState()
        try expect(switcher.step(candidates: eligible, current: first.id, backwards: false) == second.id,
            "The first Tab selects another window even when both belong to Codex")
        try expect(switcher.step(candidates: eligible, current: first.id, backwards: false) == third.id, "Holding Option and pressing Tab advances the selection")
        try expect(switcher.step(candidates: eligible, current: first.id, backwards: false) == first.id, "Forward switching wraps around")
        try expect(switcher.step(candidates: eligible, current: first.id, backwards: true) == third.id, "Shift-Tab traverses in reverse")
        first.lastVisited = Date(timeIntervalSince1970: 400)
        try expect(switcher.step(candidates: [third.id, first.id, second.id], current: first.id, backwards: false) == first.id,
            "Visit updates cannot reorder an in-progress selection gesture")
        switcher.reset()
        try expect(switcher.step(candidates: eligible, current: nil, backwards: false) == first.id, "Switching from an untracked app selects the most recent managed window")
        switcher.reset()
        try expect(switcher.step(candidates: eligible, current: first.id, backwards: true) == third.id, "Reverse switching starts at the end")
        try expect(switcher.step(candidates: [first.id, second.id], current: first.id, backwards: false) != third.id,
            "A window that disappears during selection cannot be committed")
        switcher.reset()
        try expect(switcher.step(candidates: [], current: nil, backwards: false) == nil, "An empty board has no focus target")

        var navigationFolders = FolderState(folders: [WindowFolder(id: customers.id, name: "Kunder", expanded: false)])
        navigationFolders.assign(second.id, to: customers.id)
        navigationFolders.assign(third.id, to: customers.id)
        let collapsedRows = BoardNavigation.rows(active: [first, second, third], paused: [paused], folders: navigationFolders.folders,
            state: navigationFolders, searching: false, pausedExpanded: true)
        try expect(collapsedRows == [.window(first.id), .folder(customers.id), .pausedSection, .window(paused.id)],
            "Arrow navigation follows the visible list and skips collapsed folder contents")
        let searchedRows = BoardNavigation.rows(active: [first, second, third], paused: [], folders: navigationFolders.folders,
            state: navigationFolders, searching: true, pausedExpanded: true)
        try expect(searchedRows == [.window(first.id), .folder(customers.id), .window(second.id), .window(third.id)],
            "Search results inside a collapsed folder remain keyboard-accessible")
        let forcedRows = BoardNavigation.rows(active: [first, second, third], paused: [], folders: navigationFolders.folders,
            state: navigationFolders, searching: false, pausedExpanded: true, forcedFolder: customers.id)
        try expect(forcedRows == searchedRows, "Option-Tab can reveal a selected window inside a collapsed folder")
        try expect(BoardNavigation.moved(in: collapsedRows, from: .window(first.id), delta: 1) == .folder(customers.id), "Down selects the next visible folder")
        try expect(BoardNavigation.moved(in: collapsedRows, from: .folder(customers.id), delta: -1) == .window(first.id), "Up selects the previous visible window")
        try expect(BoardNavigation.moved(in: collapsedRows, from: .window(first.id), delta: -1) == .window(first.id), "Up stops at the start of the list")
        try expect(BoardNavigation.moved(in: collapsedRows, from: .window(paused.id), delta: 1) == .window(paused.id), "Down stops at the end of the list")
        try expect(BoardNavigation.moved(in: [], from: nil, delta: 1) == nil, "An empty navigation list has no selected row")
        let pausedCollapsedRows = BoardNavigation.rows(active: [], paused: [paused], folders: [], state: navigationFolders, searching: false, pausedExpanded: false)
        try expect(pausedCollapsedRows == [.pausedSection], "Collapsed paused sections do not expose hidden rows to arrow navigation")

        let corrupt = Data("{broken board".utf8)
        try corrupt.write(to: url)
        do {
            _ = try BoardStorage.load(from: url)
            throw TestFailure.failed("Corrupt data must not look like an empty board")
        } catch is DecodingError { }
        try expect(try Data(contentsOf: url) == corrupt, "A failed read leaves the original file intact")
        print("PASS: \(checks) persistence, folder, window-switcher and reconnection checks")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
        guard try condition() else { throw TestFailure.failed(description) }
        checks += 1
    }
    enum TestFailure: Error { case failed(String) }
}
