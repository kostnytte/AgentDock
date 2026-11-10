import AppKit
import SwiftUI

extension BoardStore {
    var archiveURL: URL { storageURL.deletingLastPathComponent().appendingPathComponent("archive.json") }
    func isArchived(_ id: UUID) -> Bool { archiveState.contains(id) }
    var unarchivedCards: [WindowCard] { cards.filter { !isArchived($0.id) } }
    var archivedCards: [WindowCard] {
        cards.enumerated().filter { isArchived($0.element.id) }.sorted {
            let left = archiveState.archivedAt[$0.element.id.uuidString] ?? .distantPast
            let right = archiveState.archivedAt[$1.element.id.uuidString] ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }
    var unavailableCards: [WindowCard] { permission ? unarchivedCards.filter { !connected($0) } : [] }

    private func updateArchive(_ next: ArchiveState, rememberUndo: Bool = true) -> Bool {
        guard archiveStorageError == nil else { message = archiveStorageError; return false }
        do { if !preview { try ArchiveStorage.save(next, to: archiveURL) } }
        catch { message = "Arkivendringen kunne ikke lagres: \(error.localizedDescription)"; return false }
        archiveUndo = rememberUndo ? archiveState : nil
        archiveState = next
        message = nil
        return true
    }
    @discardableResult func archiveCards(_ ids: Set<UUID>) -> Bool {
        let valid = unarchivedCards.filter { ids.contains($0.id) }
        guard !valid.isEmpty else { return false }
        var next = archiveState
        let now = Date()
        for card in valid { next.archivedAt[card.id.uuidString] = now }
        return updateArchive(next)
    }
    @discardableResult func restoreArchived(_ ids: Set<UUID>) -> Bool {
        let valid = archivedCards.filter { ids.contains($0.id) }
        guard !valid.isEmpty else { return false }
        var next = archiveState
        for card in valid { next.archivedAt.removeValue(forKey: card.id.uuidString) }
        return updateArchive(next)
    }
    @discardableResult func undoArchiveChange() -> Bool {
        guard let old = archiveUndo else { return false }
        return updateArchive(old, rememberUndo: false)
    }

    var effectiveSwitcherScope: WindowScope {
        if case .folder(let id) = switcherScope, !folderState.folders.contains(where: { $0.id == id }) { return .all }
        return switcherScope
    }
    var switcherScopes: [WindowScope] { [.all, .unfiled] + folderState.folders.map { .folder($0.id) } }
    func scopeName(_ scope: WindowScope) -> String {
        switch scope {
        case .all: return "Alle"
        case .unfiled: return "Uten mappe"
        case .folder(let id): return folderState.folders.first(where: { $0.id == id })?.name ?? "Alle"
        }
    }
    func scopeCount(_ scope: WindowScope) -> Int {
        unarchivedCards.filter { !$0.paused && connected($0) && scope.contains($0.id, folders: folderState) }.count
    }
    var switcherCandidateIDs: [UUID] {
        let eligible = unarchivedCards.filter { effectiveSwitcherScope.contains($0.id, folders: folderState) }
        return WindowSwitcherState.candidates(eligible, connected: Set(eligible.filter { connected($0) }.map(\.id)))
    }
    func setSwitcherScope(_ scope: WindowScope) {
        guard switcherScopes.contains(scope) else { return }
        switcherSelectionFromPointer = false
        switcherScope = scope
        windowSwitcher.reset()
        switcherSelectionID = windowSwitcher.step(candidates: switcherCandidateIDs, current: nil, backwards: false)
    }
    func cycleSwitcherScope(_ delta: Int) {
        let scopes = switcherScopes
        let index = scopes.firstIndex(of: effectiveSwitcherScope) ?? 0
        setSwitcherScope(scopes[(index + delta + scopes.count) % scopes.count])
    }

    func card(for window: LiveWindow) -> WindowCard? {
        guard let id = connections.first(where: { $0.value == window.id })?.key else { return nil }
        return cards.first { $0.id == id }
    }
    var windowSearchEntries: [WindowSearchEntry] {
        liveWindows.map { window in
            let existing = card(for: window)
            return WindowSearchEntry(id: window.id, title: window.title, appName: window.appName,
                alias: existing?.name ?? "", folder: existing.flatMap { folderName(for: $0) } ?? "",
                pinned: existing != nil, archived: existing.map { isArchived($0.id) } ?? false)
        }.filter { WindowSearch.matches($0, query: windowSearchQuery) }
            .sorted {
                if ($0.pinned && !$0.archived) != ($1.pinned && !$1.archived) { return $0.pinned && !$0.archived }
                let left = $0.appName + " " + $0.displayName
                let right = $1.appName + " " + $1.displayName
                let comparison = left.localizedStandardCompare(right)
                return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
            }
    }
    var selectedSearchWindow: LiveWindow? {
        let entries = windowSearchEntries
        guard let id = entries.first(where: { $0.id == searchSelectionID })?.id ?? entries.first?.id else { return nil }
        return liveWindows.first { $0.id == id }
    }
    func moveSearchSelection(_ delta: Int) {
        searchSelectionID = WindowSearch.moved(in: windowSearchEntries.map(\.id), current: selectedSearchWindow?.id, delta: delta)
    }
    func openSearchSelection() {
        guard let window = selectedSearchWindow else { return }
        openLiveWindow(window)
    }
    func openLiveWindow(_ window: LiveWindow) {
        if let existing = card(for: window), !isArchived(existing.id) { focus(existing); return }
        guard !preview else { return }
        windowChosen?()
        WindowAccess.focus(window) { [weak self] success in
            guard let self else { return }
            if !success { self.message = "Vinduet kunne ikke hentes frem. Hent vinduer på nytt og prøv igjen."; self.focusFailed?() }
        }
    }

    // Name + folder are committed before publishing the new card. If a later
    // metadata write fails, restore earlier files and leave in-memory state
    // unchanged. Never erase a board after a failed initial read.
    @discardableResult func savePinnedWindow(_ window: LiveWindow, name: String, folder: UUID?) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { message = "Skriv et navn på vinduet."; return nil }
        guard storageError == nil, folderStorageError == nil, archiveStorageError == nil else {
            message = storageError ?? folderStorageError ?? archiveStorageError
            return nil
        }
        guard folder == nil || folderState.folders.contains(where: { $0.id == folder }) else {
            message = "Mappen finnes ikke lenger. Velg en annen mappe."; return nil
        }
        let live = liveWindows.first { $0.pid == window.pid && CFEqual($0.element, window.element) } ?? window
        let existing = card(for: live)
        var nextCards = cards
        let id: UUID
        if let existing, let index = nextCards.firstIndex(where: { $0.id == existing.id }) {
            id = existing.id
            nextCards[index].name = clean
            nextCards[index].paused = false
            nextCards[index].windowTitle = live.title
        } else {
            let card = WindowCard(bundleID: live.bundleID, appName: live.appName, windowTitle: live.title, name: clean)
            id = card.id
            nextCards.append(card)
        }
        var nextFolders = folderState
        nextFolders.assign(id, to: folder)
        if let folder, let index = nextFolders.folders.firstIndex(where: { $0.id == folder }) { nextFolders.folders[index].expanded = true }
        var nextArchive = archiveState
        nextArchive.archivedAt.removeValue(forKey: id.uuidString)
        if !preview {
            var wroteFolders = false
            var wroteArchive = false
            do {
                try FolderStorage.save(nextFolders, to: foldersURL); wroteFolders = true
                if nextArchive != archiveState { try ArchiveStorage.save(nextArchive, to: archiveURL); wroteArchive = true }
                try BoardStorage.save(nextCards, to: storageURL)
            } catch {
                var rollbackFailed = false
                if wroteFolders { do { try FolderStorage.save(folderState, to: foldersURL) } catch { rollbackFailed = true } }
                if wroteArchive { do { try ArchiveStorage.save(archiveState, to: archiveURL) } catch { rollbackFailed = true } }
                message = "Vinduet kunne ikke lagres: \(error.localizedDescription)"
                if rollbackFailed {
                    folderStorageError = "En metadataendring kunne ikke rulles tilbake. Start appen på nytt før du endrer mapper."
                    message = folderStorageError
                }
                return nil
            }
        }
        cards = nextCards
        folderState = nextFolders
        archiveState = nextArchive
        if !liveWindows.contains(where: { $0.id == live.id }) { liveWindows.append(live) }
        connections[id] = live.id
        keyboardSelection = .window(id)
        message = nil
        return id
    }
}
