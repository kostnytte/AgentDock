import AppKit
import Foundation

@main
struct ShortcutTests {
    static var checks = 0
    enum Failure: Error { case failed(String) }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure.failed(message) }
        checks += 1
    }
    static func pumpUntil(_ condition: () -> Bool) {
        let limit = Date().addingTimeInterval(1)
        while !condition() && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDock-shortcuts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("Kundenotat.txt")
        try Data("Egne testdata".utf8).write(to: file)
        let target = try ShortcutSupport.makeTarget(url: file, kind: .file)
        try expect(target.kind == .file && target.path == file.path, "Choose a closed local file without requiring an open window")
        try expect(target.bookmark != nil && ShortcutSupport.resolvedURL(target) == file, "File bookmark resolves to the selected file")
        try expect(ShortcutSupport.defaultName(target) == "Kundenotat.txt", "A file shortcut starts with its real filename")
        let alias = base.appendingPathComponent("Alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        let aliasTarget = try ShortcutSupport.makeTarget(url: alias, kind: .file)
        try expect(ShortcutSupport.sameTarget(target, aliasTarget), "Symlinks to the same file do not create duplicate shortcuts")
        var rejectedDirectory = false
        do { _ = try ShortcutSupport.makeTarget(url: base, kind: .file) } catch { rejectedDirectory = true }
        try expect(rejectedDirectory, "The file chooser cannot silently create folder launchers")
        var rejectedMissing = false
        do { _ = try ShortcutSupport.makeTarget(url: base.appendingPathComponent("missing.txt"), kind: .file) } catch { rejectedMissing = true }
        try expect(rejectedMissing, "A missing file cannot be pinned")
        var rejectedNonApp = false
        do { _ = try ShortcutSupport.makeTarget(url: file, kind: .application) } catch { rejectedNonApp = true }
        try expect(rejectedNonApp, "An app target must actually be an app bundle")

        let fakeApp = base.appendingPathComponent("TestEditor.app")
        try FileManager.default.createDirectory(at: fakeApp.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.agentdock.editor", "CFBundleName": "TestEditor",
            "CFBundleExecutable": "TestEditor", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: fakeApp.appendingPathComponent("Contents/Info.plist"))
        try Data().write(to: fakeApp.appendingPathComponent("Contents/MacOS/TestEditor"))
        let appTarget = try ShortcutSupport.makeTarget(url: fakeApp, kind: .application)
        try expect(appTarget.kind == .application && appTarget.applicationBundleID == "test.agentdock.editor", "A closed app is stored as an application target")
        try expect(ShortcutSupport.defaultName(appTarget) == "TestEditor", "The app name omits the app extension")
        try expect(try ShortcutSupport.makeTarget(url: fakeApp, kind: .file).kind == .application, "An app selected from the file picker remains an app shortcut")
        let ownApp = base.appendingPathComponent("AgentDock.app")
        try FileManager.default.createDirectory(at: ownApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "no.magne.agentdock", "CFBundleExecutable": "AgentDock"],
            format: .xml, options: 0).write(to: ownApp.appendingPathComponent("Contents/Info.plist"))
        var rejectedSelf = false
        do { _ = try ShortcutSupport.makeTarget(url: ownApp, kind: .application) } catch { rejectedSelf = true }
        try expect(rejectedSelf, "AgentDock cannot create a launcher that opens another copy of itself")

        let boardURL = base.appendingPathComponent("data/board.json")
        let original = WindowCard(bundleID: "test.window", appName: "Editor", windowTitle: "Arbeidsvindu", name: "Mitt vindu", paused: true)
        try BoardStorage.save([original], to: boardURL)
        let boardBytes = try Data(contentsOf: boardURL)
        let store = BoardStore(storageURL: boardURL, monitoring: false)
        try expect(!store.permission, "A non-monitoring test store never queries Accessibility during initialization")
        try expect(store.shortcutState == ShortcutState() && store.cards == [original], "Old boards load without shortcut migration")
        try expect(try Data(contentsOf: boardURL) == boardBytes, "Reading old boards preserves their exact bytes")
        _ = store.saveFolder(id: nil, name: "Kunder", cards: [])
        let folder = store.folderState.folders[0].id
        let id = store.saveShortcut(target, name: "  Kundenotat  ", folder: folder)!
        let fileCard = store.cards.first { $0.id == id }!
        try expect(fileCard.name == "Kundenotat" && fileCard.appName == "Fil", "Save a named file shortcut with an explicit type")
        try expect(store.folderState.folderID(for: id) == folder, "File shortcut belongs to the chosen folder")
        try expect(store.connected(fileCard) && !store.permission, "A file shortcut is ready without Accessibility permission")
        try expect(store.connections[id] == nil && fileCard.bundleID.hasPrefix("no.magne.agentdock.shortcut."), "Shortcut cannot claim an unrelated AX window")
        try expect(try ShortcutStorage.load(from: store.shortcutsURL)[id] == target, "Shortcut metadata and bookmark survive disk persistence")
        let duplicate = store.saveShortcut(aliasTarget, name: "Nytt navn", folder: folder)
        try expect(duplicate == id && store.cards.count == 2, "Pinning the same file again updates the original card")
        let reopened = BoardStore(storageURL: boardURL, monitoring: false)
        try expect(reopened.shortcutState[id] != nil && reopened.cards.first(where: { $0.id == id })?.name == "Nytt navn", "Shortcut identity and custom name survive restart")
        try expect(reopened.folderState.folderID(for: id) == folder, "Shortcut folder survives restart")
        store.togglePause(id)
        _ = store.archiveCards([id])
        try expect(store.saveShortcut(target, name: "Tilbake", folder: folder) == id && !store.isArchived(id), "Pinning an archived shortcut restores its existing identity")
        try expect(!store.cards.first(where: { $0.id == id })!.paused, "Restored shortcut is active again")
        try expect(store.cards.first == original, "Shortcut operations preserve existing window cards")
        let beforeInvalid = store.cards
        try expect(store.saveShortcut(target, name: " ", folder: folder) == nil && store.cards == beforeInvalid, "Empty shortcut name never persists a partial card")
        try expect(store.saveShortcut(target, name: "Navn", folder: UUID()) == nil && store.cards == beforeInvalid, "A removed folder never creates a partial shortcut")

        let otherFile = base.appendingPathComponent("Other.txt")
        try Data("Andre testdata".utf8).write(to: otherFile)
        let otherTarget = try ShortcutSupport.makeTarget(url: otherFile, kind: .file)
        let otherID = store.saveShortcut(otherTarget, name: "Annet notat", folder: nil)!
        try expect(store.saveShortcut(otherTarget, name: "Skal ikke slå sammen", folder: folder, editingID: id) == nil,
            "Relinking cannot silently overwrite a different card for the same target")
        let repaired = store.saveShortcut(appTarget, name: "Min editor", folder: folder, editingID: id)
        try expect(repaired == id && store.shortcutState[id]?.kind == .application, "Relinking preserves the original card ID and folder")
        let shortcutCard = store.cards.first { $0.id == id }!
        var selectedKind: ShortcutKind?
        var selectedURL: URL?
        store.shortcutOpener = { selected, url, completion in selectedKind = selected.kind; selectedURL = url; completion(true, nil) }
        store.focus(shortcutCard)
        pumpUntil { store.launchingShortcutID == nil }
        try expect(selectedKind == .application && selectedURL?.path == fakeApp.path, "Selecting an app card requests application opening even without Accessibility")
        try expect(store.cards.first(where: { $0.id == id })!.lastVisited != nil, "Successful open updates visit order")
        let beforeFailure = store.cards
        var failureShown = false
        store.focusFailed = { failureShown = true }
        store.shortcutOpener = { _, _, completion in completion(false, "Testfeil ved åpning") }
        store.focus(shortcutCard)
        pumpUntil { store.launchingShortcutID == nil }
        try expect(failureShown && store.message == "Testfeil ved åpning", "Failed app launch is reported to the user")
        try expect(store.cards == beforeFailure, "A failed launch never removes or rewrites the card")
        var staleCallback: ((Bool, String?) -> Void)?
        store.shortcutOpener = { _, _, completion in staleCallback = completion }
        store.focus(shortcutCard)
        store.shortcutOpener = { _, _, completion in completion(true, nil) }
        store.focus(store.cards.first { $0.id == otherID }!)
        pumpUntil { store.launchingShortcutID == nil }
        staleCallback?(false, "Gammel feil")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        try expect(store.message == nil, "An old asynchronous launch response cannot override a newer successful selection")

        let failingBase = base.appendingPathComponent("failure")
        let failingURL = failingBase.appendingPathComponent("board.json")
        try BoardStorage.save([original], to: failingURL)
        let failing = BoardStore(storageURL: failingURL, monitoring: false)
        let oldTargets = failing.shortcutState
        let oldFolders = failing.folderState
        try FileManager.default.removeItem(at: failingURL)
        try FileManager.default.createDirectory(at: failingURL, withIntermediateDirectories: false)
        try expect(failing.saveShortcut(target, name: "Må feile", folder: nil) == nil, "Board write failure aborts shortcut creation")
        try expect(failing.cards == [original] && failing.shortcutState == oldTargets, "Failed shortcut save leaves in-memory state intact")
        try expect(try ShortcutStorage.load(from: failing.shortcutsURL) == oldTargets && FolderStorage.load(from: failing.foldersURL) == oldFolders,
            "Shortcut and folder metadata are rolled back after a late board write failure")
        let corruptBase = base.appendingPathComponent("corrupt")
        let corruptBoard = corruptBase.appendingPathComponent("board.json")
        try BoardStorage.save([original], to: corruptBoard)
        let invalid = Data("broken shortcuts".utf8)
        try invalid.write(to: corruptBase.appendingPathComponent("shortcuts.json"))
        let corrupt = BoardStore(storageURL: corruptBoard, monitoring: false)
        try expect(corrupt.shortcutStorageError != nil && corrupt.saveShortcut(target, name: "Ikke overskriv", folder: nil) == nil,
            "Damaged shortcut data is reported and never overwritten")
        try expect(try Data(contentsOf: corrupt.shortcutsURL) == invalid, "Corrupt shortcut bytes are preserved exactly")
        try FileManager.default.removeItem(at: otherFile)
        let missingCard = store.cards.first { $0.id == otherID }!
        try expect(!store.connected(missingCard), "A deleted target becomes unavailable without removing its card")
        var attemptedMissingOpen = false
        store.shortcutOpener = { _, _, _ in attemptedMissingOpen = true }
        store.focus(missingCard)
        try expect(!attemptedMissingOpen && store.cards.contains(missingCard), "Missing targets are not launched and can be relinked")
        let moved = base.appendingPathComponent("Flyttet kundenotat.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        try expect(ShortcutSupport.resolvedURL(target) == moved, "A bookmark follows a file renamed within the same folder")
        print("PASS: \(checks) application/file shortcut persistence, resolution and launch-contract checks")
    }
}
