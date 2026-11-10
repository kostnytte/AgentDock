import Foundation
import ApplicationServices

@main
struct WorkflowTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure.failed(message) }
        checks += 1
    }
    enum Failure: Error { case failed(String) }

    static func main() throws {
        let store = BoardStore(preview: true)
        store.refresh(discover: true)
        try expect(store.permission, "Preview discovery never queries or changes real Accessibility permission")
        let originalCards = store.cards
        let first = store.cards[0]
        let paused = store.cards.first { $0.paused }!
        let customer = store.folderState.folders[0]
        let customerCard = store.cards[1]
        let folderSnapshot = store.folderState
        try expect(store.archiveCards([first.id, paused.id]), "Archive multiple active/paused cards in one operation")
        try expect(store.cards == originalCards && store.folderState == folderSnapshot, "Archiving does not rewrite cards or folder membership")
        try expect(store.archivedCards.count == 2 && !store.active.contains(first) && !store.paused.contains(paused), "Archive hides cards from active and paused lists")
        try expect(!store.navigationRows.contains(.window(first.id)), "Archived cards are absent from arrow navigation")
        _ = store.stepWindowSwitcher(backwards: false)
        try expect(!store.switcherCards.contains(first) && !store.switcherCards.contains(paused), "Archived cards never enter the global window switcher")
        store.cancelWindowSwitcher()
        store.jump(1)
        try expect(store.focusedID == customerCard.id, "Number shortcuts skip archived cards")
        try expect(store.undoArchiveChange() && store.archivedCards.isEmpty, "Undo restores an entire bulk archive")
        try expect(store.cards == originalCards, "Undo preserves original card order, pause and timestamps")
        try expect(store.archiveCards([customerCard.id, paused.id]), "Archive a folder member alongside a paused card")
        try expect(store.restoreArchived([customerCard.id]) && store.folderState.folderID(for: customerCard.id) == customer.id,
            "Restoring returns a card to its original folder")
        try expect(store.restoreArchived([paused.id]) && store.cards.first(where: { $0.id == paused.id })!.paused,
            "Restoring preserves a paused card's pause state")
        try expect(!store.archiveCards([UUID()]) && !store.restoreArchived([UUID()]), "Unknown selections do not mutate the archive")

        store.setSwitcherScope(.folder(customer.id))
        try expect(Set(store.switcherCards.map(\.id)) == Set([store.cards[1].id, store.cards[2].id]), "Folder-scoped switcher excludes every other window")
        try expect(store.scopeCount(.folder(customer.id)) == 2, "Folder count matches eligible connected active windows")
        let withinFolder = store.switcherSelectionID
        _ = store.stepWindowSwitcher(backwards: false)
        try expect(store.switcherSelectionID != withinFolder && store.switcherCards.count == 2, "Tab wraps within the chosen folder")
        _ = store.archiveCards([store.cards[1].id])
        store.setSwitcherScope(.folder(customer.id))
        try expect(store.switcherCards.map(\.id) == [store.cards[2].id], "A folder filter also excludes archived windows")
        store.setSwitcherScope(.unfiled)
        try expect(store.switcherCards.allSatisfy { store.folderState.folderID(for: $0.id) == nil }, "Unfiled filter only includes unfiled windows")
        store.setSwitcherScope(.all)
        try expect(store.switcherCards.count == store.unarchivedCards.filter { !$0.paused }.count, "All scope recovers the full eligible list")
        store.setSwitcherScope(.folder(customer.id))
        store.dissolveFolder(customer.id)
        try expect(store.effectiveSwitcherScope == .all, "A removed folder safely falls back to All")
        let empty = WindowFolder(name: "Tom mappe")
        store.folderState.folders.append(empty)
        store.setSwitcherScope(.folder(empty.id))
        try expect(store.switcherCards.isEmpty && store.switcherSelectionID == nil, "An empty scope has no stale selection")
        store.cycleSwitcherScope(1)
        try expect(store.effectiveSwitcherScope == .all, "Scope arrows wrap from the last folder to All")
        store.cancelWindowSwitcher()

        let preserved = BoardStore(preview: true)
        let preservedFolder = preserved.folderState.folders[0]
        let archivedMember = preserved.cards[1]
        _ = preserved.archiveCards([archivedMember.id])
        _ = preserved.saveFolder(id: preservedFolder.id, name: "Nytt mappenavn", cards: [preserved.cards[2].id])
        try expect(preserved.folderState.folderID(for: archivedMember.id) == preservedFolder.id,
            "Editing visible folder members never unfiles archived cards")
        preserved.permission = false
        try expect(preserved.unavailableCards.isEmpty, "Missing Accessibility permission is not mistaken for closed windows during cleanup")

        let entry = WindowSearchEntry(id: UUID(), title: "Teknisk gjennomgang", appName: "Codex", alias: "Årsoppgjør", folder: "Kunder", pinned: true, archived: false)
        try expect(WindowSearch.matches(entry, query: "codex kunder"), "Search matches multiple terms across app and folder")
        try expect(WindowSearch.matches(entry, query: "ARSOPPGJOR"), "Search handles case and Norwegian diacritics")
        try expect(WindowSearch.matches(entry, query: " teknisk  "), "Search includes original title and ignores surrounding spaces")
        try expect(!WindowSearch.matches(entry, query: "codex mangler"), "Every search term must match")
        let ids = [UUID(), UUID()]
        try expect(WindowSearch.moved(in: ids, current: nil, delta: 1) == ids[0], "Search navigation starts at the first result")
        try expect(WindowSearch.moved(in: ids, current: ids[1], delta: 1) == ids[1], "Search navigation clamps at the last result")
        try expect(WindowSearch.moved(in: [], current: ids[0], delta: -1) == nil, "Empty search never retains a vanished result")
        let search = BoardStore(preview: true)
        search.windowSearchQuery = "kundemøte"
        try expect(search.windowSearchEntries.count == 1 && !search.windowSearchEntries[0].pinned,
            "Search finds a live window that has never been pinned")
        search.windowSearchQuery = "Kunder"
        try expect(search.windowSearchEntries.count == 2, "Live window search includes saved folder names")
        let searchCard = search.cards[1]
        _ = search.archiveCards([searchCard.id])
        search.windowSearchQuery = searchCard.name
        try expect(search.windowSearchEntries.first?.archived == true, "A still-open archived window remains discoverable and is labelled archived")

        let pin = BoardStore(preview: true)
        let unpinned = pin.liveWindows.last!
        let targetFolder = pin.folderState.folders[0].id
        let before = pin.cards
        try expect(pin.savePinnedWindow(unpinned, name: " ", folder: targetFolder) == nil && pin.cards == before,
            "An empty name does not pin or mutate any card")
        try expect(pin.savePinnedWindow(unpinned, name: "Notat", folder: UUID()) == nil && pin.cards == before,
            "A vanished destination folder does not create a partial card")
        let id = pin.savePinnedWindow(unpinned, name: "  Kundemøte  ", folder: targetFolder)!
        try expect(pin.cards.count == before.count + 1 && pin.cards.last!.name == "Kundemøte", "Pin accepts a custom trimmed name")
        try expect(pin.folderState.folderID(for: id) == targetFolder, "Pin saves the chosen folder alongside the name")
        try expect(pin.savePinnedWindow(unpinned, name: "Nytt navn", folder: nil) == id && pin.cards.count == before.count + 1,
            "Pinning the same native window updates the existing card without duplication")
        pin.togglePause(id)
        _ = pin.archiveCards([id])
        try expect(pin.savePinnedWindow(unpinned, name: "Tilbake", folder: targetFolder) == id && !pin.isArchived(id),
            "Pinning an archived native window restores its original identity")
        try expect(!pin.cards.first(where: { $0.id == id })!.paused && pin.folderState.folderID(for: id) == targetFolder,
            "Restored pin is active and placed in the selected folder")

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDock-workflows-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let boardURL = base.appendingPathComponent("board.json")
        let foldersURL = base.appendingPathComponent("folders.json")
        let archiveURL = base.appendingPathComponent("archive.json")
        try BoardStorage.save(originalCards, to: boardURL)
        try FolderStorage.save(folderSnapshot, to: foldersURL)
        let originalBoardBytes = try Data(contentsOf: boardURL)
        let persisted = BoardStore(storageURL: boardURL, monitoring: false)
        try expect(try ArchiveStorage.load(from: archiveURL) == ArchiveState(), "An existing installation needs no archive migration")
        try expect(persisted.archiveCards([first.id, customerCard.id]), "A bulk archive persists successfully")
        try expect(try Data(contentsOf: boardURL) == originalBoardBytes, "Archiving leaves the original board bytes unchanged")
        let reopened = BoardStore(storageURL: boardURL, monitoring: false)
        try expect(reopened.isArchived(first.id) && reopened.isArchived(customerCard.id), "Archive mask survives restart")
        try expect(reopened.cards == originalCards && reopened.folderState == folderSnapshot, "Restart preserves original names, pause, order and folder membership")
        try expect(reopened.restoreArchived([first.id]) && !(try ArchiveStorage.load(from: archiveURL)).contains(first.id), "Restoration is persisted")
        let invalid = Data("{bad archive".utf8)
        try invalid.write(to: archiveURL)
        let damaged = BoardStore(storageURL: boardURL, monitoring: false)
        try expect(damaged.archiveStorageError != nil && !damaged.archiveCards([first.id]), "Corrupt archive is reported and never overwritten")
        try expect(try Data(contentsOf: archiveURL) == invalid, "Invalid archive bytes are retained exactly")

        let pinBase = base.appendingPathComponent("pin")
        let pinURL = pinBase.appendingPathComponent("board.json")
        try BoardStorage.save([], to: pinURL)
        let diskPin = BoardStore(storageURL: pinURL, monitoring: false)
        let fake = LiveWindow(id: UUID(), element: AXUIElementCreateApplication(79001), pid: 79001,
            bundleID: "test.editor", appName: "Editor", title: "Original tittel")
        _ = diskPin.saveFolder(id: nil, name: "Kunder", cards: [])
        let diskFolder = diskPin.folderState.folders[0].id
        let saved = diskPin.savePinnedWindow(fake, name: "Min oppgave", folder: diskFolder)!
        try expect(try BoardStorage.load(from: pinURL).first?.name == "Min oppgave", "Named pin persists the chosen name")
        try expect(try FolderStorage.load(from: pinBase.appendingPathComponent("folders.json" )).folderID(for: saved) == diskFolder,
            "Named pin persists the chosen membership")
        let originalDiskCards = diskPin.cards
        let originalDiskFolders = diskPin.folderState
        try FileManager.default.removeItem(at: pinURL)
        try FileManager.default.createDirectory(at: pinURL, withIntermediateDirectories: false)
        try expect(diskPin.savePinnedWindow(fake, name: "Skal feile", folder: nil) == nil, "A board write failure is returned to the editor")
        try expect(diskPin.cards == originalDiskCards && diskPin.folderState == originalDiskFolders, "Failed save leaves in-memory card and folder data untouched")
        try expect(try FolderStorage.load(from: pinBase.appendingPathComponent("folders.json")) == originalDiskFolders, "Earlier folder write is rolled back when board write fails")
        let archiveFailureBase = base.appendingPathComponent("archive-failure")
        let archiveFailureURL = archiveFailureBase.appendingPathComponent("board.json")
        try BoardStorage.save(originalCards, to: archiveFailureURL)
        let noArchiveWrite = BoardStore(storageURL: archiveFailureURL, monitoring: false)
        try FileManager.default.createDirectory(at: noArchiveWrite.archiveURL, withIntermediateDirectories: false)
        try expect(!noArchiveWrite.archiveCards([first.id]) && !noArchiveWrite.isArchived(first.id), "A failed archive write never hides an unsaved card")
        print("PASS: \(checks) pin, folder-scope, window-search and archive workflow checks")
    }
}
