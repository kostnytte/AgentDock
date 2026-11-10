import AppKit
import SwiftUI

extension BoardStore {
    var shortcutsURL: URL { storageURL.deletingLastPathComponent().appendingPathComponent("shortcuts.json") }
    func shortcut(for card: WindowCard) -> ShortcutTarget? { shortcutState[card.id] }
    func isShortcut(_ id: UUID) -> Bool { shortcutState[id] != nil }
    func iconURL(for card: WindowCard) -> URL? {
        if let target = shortcut(for: card) { return ShortcutSupport.resolvedURL(target) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: card.bundleID)
    }
    func subtitle(for card: WindowCard) -> String {
        if let target = shortcut(for: card) {
            let status = launchingShortcutID == card.id ? "Åpner …" : connected(card) ? "Åpnes ved valg" : "Mangler · velg mål på nytt"
            return [target.kind.label, card.project, status].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [card.appName, card.project, connected(card) ? "" : "Utilgjengelig"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func existingShortcut(for target: ShortcutTarget) -> WindowCard? {
        cards.first { card in shortcut(for: card).map { ShortcutSupport.sameTarget($0, target) } ?? false }
    }

    @discardableResult func saveShortcut(_ target: ShortcutTarget, name: String, folder: UUID?, editingID: UUID? = nil) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { message = "Skriv et navn på snarveien."; return nil }
        guard storageError == nil, folderStorageError == nil, archiveStorageError == nil, shortcutStorageError == nil else {
            message = storageError ?? folderStorageError ?? archiveStorageError ?? shortcutStorageError; return nil
        }
        guard ShortcutSupport.resolvedURL(target) != nil else { message = ShortcutSupport.Failure.missing.localizedDescription; return nil }
        guard folder == nil || folderState.folders.contains(where: { $0.id == folder }) else { message = "Mappen finnes ikke lenger."; return nil }
        if let editingID, !isShortcut(editingID) { message = "Snarveien finnes ikke lenger."; return nil }
        let duplicate = existingShortcut(for: target)
        if let editingID, let duplicate, duplicate.id != editingID {
            message = "Målet er allerede festet som «\(duplicate.name)». Velg det eksisterende kortet."; return nil
        }
        let existingID = editingID ?? duplicate?.id
        var nextCards = cards
        let id: UUID
        if let existingID, let index = nextCards.firstIndex(where: { $0.id == existingID }) {
            id = existingID
            nextCards[index].name = clean
            nextCards[index].appName = target.kind.label
            nextCards[index].windowTitle = target.path
            nextCards[index].bundleID = "no.magne.agentdock.shortcut.\(target.kind.rawValue)"
            nextCards[index].paused = false
        } else {
            let card = WindowCard(bundleID: "no.magne.agentdock.shortcut.\(target.kind.rawValue)",
                appName: target.kind.label, windowTitle: target.path, name: clean)
            id = card.id
            nextCards.append(card)
        }
        var nextTargets = shortcutState
        nextTargets[id] = target
        var nextFolders = folderState
        nextFolders.assign(id, to: folder)
        if let folder, let index = nextFolders.folders.firstIndex(where: { $0.id == folder }) { nextFolders.folders[index].expanded = true }
        var nextArchive = archiveState
        nextArchive.archivedAt.removeValue(forKey: id.uuidString)
        if !preview {
            var wroteTargets = false, wroteFolders = false, wroteArchive = false
            do {
                try ShortcutStorage.save(nextTargets, to: shortcutsURL); wroteTargets = true
                try FolderStorage.save(nextFolders, to: foldersURL); wroteFolders = true
                if nextArchive != archiveState { try ArchiveStorage.save(nextArchive, to: archiveURL); wroteArchive = true }
                try BoardStorage.save(nextCards, to: storageURL)
            } catch {
                var rollbackFailed = false
                if wroteTargets { do { try ShortcutStorage.save(shortcutState, to: shortcutsURL) } catch { rollbackFailed = true } }
                if wroteFolders { do { try FolderStorage.save(folderState, to: foldersURL) } catch { rollbackFailed = true } }
                if wroteArchive { do { try ArchiveStorage.save(archiveState, to: archiveURL) } catch { rollbackFailed = true } }
                message = "Snarveien kunne ikke lagres: \(error.localizedDescription)"
                if rollbackFailed { shortcutStorageError = "En metadataendring kunne ikke rulles tilbake. Start appen på nytt før du endrer snarveier."; message = shortcutStorageError }
                return nil
            }
        }
        cards = nextCards
        shortcutState = nextTargets
        folderState = nextFolders
        archiveState = nextArchive
        connections.removeValue(forKey: id)
        keyboardSelection = .window(id)
        message = nil
        return id
    }

    func openShortcut(_ card: WindowCard, target: ShortcutTarget) {
        guard let url = ShortcutSupport.resolvedURL(target) else {
            message = "Målet til «\(card.name)» er ikke tilgjengelig. Høyreklikk og velg «Velg app eller fil på nytt …»."
            return
        }
        let request = UUID()
        shortcutOpenRequest = request
        launchingShortcutID = card.id
        message = nil
        windowChosen?()
        recordShortcutOpen("opening")
        let open = shortcutOpener ?? ShortcutSupport.open
        open(target, url) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self, self.shortcutOpenRequest == request else { return }
                self.launchingShortcutID = nil
                self.recordShortcutOpen(success ? "opened" : "failed")
                if success {
                    if let index = self.cards.firstIndex(where: { $0.id == card.id }) { self.cards[index].lastVisited = Date(); self.save() }
                } else {
                    self.message = error ?? "Snarveien kunne ikke åpnes. Kortet er bevart."
                    self.focusFailed?()
                }
            }
        }
    }
    private func recordShortcutOpen(_ result: String) {
        UserDefaults.standard.set(["result": result, "time": Date().timeIntervalSince1970] as [String: Any], forKey: "RuntimeShortcutState")
        UserDefaults.standard.synchronize()
    }
}
