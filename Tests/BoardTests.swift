import Foundation
import ApplicationServices

@main
struct BoardTests {
    static var checks = 0
    static func main() throws {
        let store = BoardStore(preview: true)
        let first = store.cards[0]
        let second = store.cards[1]
        let paused = store.cards.first { $0.paused }!
        let originals = store.cards
        store.folderState = FolderState()
        try expect(store.saveFolder(id: nil, name: "Kunder", cards: [first.id, second.id, paused.id]), "Create one folder with multiple existing windows")
        let customers = store.folderState.folders[0]
        try expect(store.cards == originals, "Filing windows preserves all existing card data, pause state and ordering")
        try expect(store.folderState.folderID(for: paused.id) == customers.id && store.cards.first(where: { $0.id == paused.id })!.paused,
            "A paused window retains both its folder and its pause state")
        try expect(!store.saveFolder(id: nil, name: " kunder ", cards: []), "Folder names are unique regardless of whitespace and case")
        store.query = "Kunder"
        try expect(Set(store.active.map(\.id)) == [first.id, second.id], "Searching a folder finds its active windows")
        try expect(store.paused.map(\.id) == [paused.id], "Searching a folder also finds its paused windows")
        store.query = ""
        store.toggleFolder(customers.id)
        try expect(!store.folderState.folders[0].expanded, "Folder collapse is stored independently of windows")
        try expect(store.saveFolder(id: customers.id, name: "Kundeprosjekter", cards: [second.id, paused.id]), "Rename folder and adjust several memberships together")
        try expect(store.folderState.folderID(for: first.id) == nil && store.folderState.folderID(for: second.id) == customers.id,
            "Unchecked windows return to the board and checked windows stay in the folder")
        store.dissolveFolder(customers.id)
        try expect(store.cards == originals && store.folderState.folders.isEmpty, "Dissolve never removes or changes any window card")
        store.undoDissolveFolder()
        try expect(store.folderState.folders.first?.name == "Kundeprosjekter" && store.folderState.folderID(for: second.id) == customers.id,
            "Undo restores the folder name and exact memberships")

        store.focusedID = first.id
        store.query = "a saved search"
        try expect(store.stepWindowSwitcher(backwards: false), "Start keyboard switching with connected cards")
        let selection = store.switcherSelectionID
        try expect(selection != nil && selection != paused.id && store.query.isEmpty, "The selection is visible and paused windows are skipped")
        let frozen = store.switcherCards.map(\.id)
        try expect(Set(frozen) == Set(originals.filter { !$0.paused }.map(\.id)), "Centered switcher includes windows from collapsed folders and excludes paused windows")
        store.cards.reverse()
        try expect(store.switcherCards.map(\.id) == frozen, "Centered switcher stays in frozen visit order when board order changes")
        store.cards = originals
        store.selectWindowSwitcher(paused.id)
        try expect(store.switcherSelectionID == selection, "A paused or unrelated card cannot be selected through the switcher")
        store.selectWindowSwitcher(first.id)
        try expect(store.switcherSelectionID == first.id, "Click selection and keyboard stepping share the same switcher state")
        _ = store.stepWindowSwitcher(backwards: false)
        try expect(store.switcherSelectionID == frozen[(frozen.firstIndex(of: first.id)! + 1) % frozen.count], "Tab continues from the explicitly selected tile")
        store.cancelWindowSwitcher()
        try expect(store.switcherCards.isEmpty, "Cancelling clears the centered switcher contents")
        try expect(store.focusedID == first.id && store.query == "a saved search", "Cancelling does not switch focus and restores the existing search")
        _ = store.stepWindowSwitcher(backwards: false)
        let committed = store.switcherSelectionID
        store.commitWindowSwitcher()
        try expect(store.focusedID == committed && store.switcherSelectionID == nil && store.query == "a saved search",
            "Commit opens exactly the selected window and clears temporary selection")
        try expect(store.cards == originals, "Folder and switcher operations preserve the original cards")
        store.query = ""
        store.keyboardSelection = .folder(customers.id)
        store.expandKeyboardSelection()
        try expect(store.folderState.folders[0].expanded, "Right arrow expands a selected folder")
        store.moveKeyboardSelection(1)
        try expect(store.keyboardSelection == .window(second.id), "Down arrow enters the expanded folder")
        store.collapseKeyboardSelection()
        try expect(store.keyboardSelection == .folder(customers.id), "Left arrow returns from a child window to its folder")
        store.collapseKeyboardSelection()
        try expect(!store.folderState.folders[0].expanded, "A second Left arrow collapses the parent folder")
        store.expandKeyboardSelection()
        store.expandKeyboardSelection()
        try expect(store.keyboardSelection == .window(second.id), "Right can move from an expanded folder to its first child")
        store.activateKeyboardSelection()
        try expect(store.focusedID == second.id, "Enter opens the selected child window")
        store.keyboardSelection = .pausedSection
        store.collapseKeyboardSelection()
        try expect(!store.pausedExpanded, "Left collapses the paused section")
        store.expandKeyboardSelection()
        store.expandKeyboardSelection()
        try expect(store.keyboardSelection == .window(paused.id), "Right enters the paused section")
        store.collapseKeyboardSelection()
        try expect(store.keyboardSelection == .pausedSection, "Left from a paused window returns to the visible paused section")
        try expect(store.cards == originals, "Arrow navigation leaves window data and pause states intact")
        store.cards = originals.map { card in var card = card; card.paused = true; return card }
        store.query = "behold dette søket"
        try expect(!store.stepWindowSwitcher(backwards: false), "No keyboard selection is offered when every window is paused")
        try expect(!store.stepWindowSwitcher(backwards: false), "Repeated Tab on an empty selection remains harmless")
        store.cancelWindowSwitcher()
        try expect(store.query == "behold dette søket", "Repeated empty gestures never erase the previous search")
        let pinBoard = BoardStore(preview: true)
        pinBoard.cards = []
        pinBoard.folderState = FolderState()
        let live = LiveWindow(id: UUID(), element: AXUIElementCreateApplication(4711), pid: 4711,
            bundleID: "test.editor", appName: "Editor", title: "Samme tittel")
        try expect(pinBoard.pin(live) && pinBoard.cards.count == 1, "Quick pin accepts a window from an app not already on the board")
        let pinnedID = pinBoard.cards[0].id
        try expect(!pinBoard.pin(live) && pinBoard.cards.count == 1, "Repeated quick pin of the same AX identity never duplicates a card")
        pinBoard.togglePause(pinnedID)
        _ = pinBoard.saveFolder(id: nil, name: "Kunder", cards: [pinnedID])
        let folder = pinBoard.folderState.folderID(for: pinnedID)
        try expect(!pinBoard.pin(live) && !pinBoard.cards[0].paused, "Quick pin resumes a paused window")
        try expect(pinBoard.cards[0].id == pinnedID && pinBoard.folderState.folderID(for: pinnedID) == folder,
            "Quick pin preserves existing card identity and folder membership")
        let secondLive = LiveWindow(id: UUID(), element: AXUIElementCreateApplication(4712), pid: 4712,
            bundleID: "test.editor", appName: "Editor", title: "Samme tittel")
        try expect(pinBoard.pin(secondLive) && pinBoard.cards.count == 2, "Different native identities sharing a title remain separate cards")
        let dragBoard = BoardStore(preview: true)
        let dragOriginals = dragBoard.cards
        let dragged = dragBoard.cards[0]
        let dragFolder = dragBoard.folderState.folders[0].id
        dragBoard.toggleFolder(dragFolder)
        let stalePayload = dragBoard.beginCardDrag(dragged.id)
        let payload = dragBoard.beginCardDrag(dragged.id)
        try expect(!dragBoard.completeCardDrop(stalePayload, to: dragFolder), "A cancelled old drag cannot move a card in a new drag session")
        try expect(!dragBoard.completeCardDrop(dragged.id.uuidString, to: dragFolder), "Foreign text matching a card ID is not accepted as a card drag")
        try expect(dragBoard.completeCardDrop(payload, to: dragFolder), "A valid card payload drops into a collapsed folder")
        try expect(dragBoard.folderState.folderID(for: dragged.id) == dragFolder && dragBoard.folderState.folders[0].expanded,
            "A successful folder drop files the card and opens the folder to show it")
        try expect(dragBoard.cards == dragOriginals && dragBoard.draggingID == nil,
            "Dropping preserves all window data and clears the drag session")
        try expect(!dragBoard.completeCardDrop(payload, to: dragFolder), "A delivered payload cannot be used twice")
        let otherFolder = WindowFolder(name: "Prosjekter")
        dragBoard.folderState.folders.append(otherFolder)
        let nextPayload = dragBoard.beginCardDrag(dragged.id)
        try expect(dragBoard.completeCardDrop(nextPayload, to: otherFolder.id) && dragBoard.folderState.folderID(for: dragged.id) == otherFolder.id,
            "A card can be dragged from one folder to another")
        let missingPayload = dragBoard.beginCardDrag(dragged.id)
        try expect(!dragBoard.completeCardDrop(missingPayload, to: UUID()) && dragBoard.folderState.folderID(for: dragged.id) == otherFolder.id,
            "Dropping onto a removed folder keeps the previous membership")
        let untouchedOrder = dragBoard.cards
        _ = dragBoard.beginCardDrag(dragged.id)
        try expect(dragBoard.cards == untouchedOrder, "Starting and cancelling a drag never changes card order")
        let picker = BoardStore(preview: true)
        _ = picker.stepWindowSwitcher(backwards: false)
        let pickerOriginals = picker.cards
        let pickerFolders = picker.folderState
        let pickerLive = picker.liveWindows.map(\.id)
        let pickerFocus = picker.focusedID
        let pickerOrder = picker.switcherCards.map(\.id)
        let hovered = pickerOrder[2]
        picker.selectWindowSwitcher(hovered, fromPointer: true)
        try expect(picker.switcherSelectionID == hovered && picker.focusedID == pickerFocus,
            "Pointer selection marks a card without activating its application")
        try expect(picker.switcherSelectionFromPointer, "Pointer selection suppresses recentering the tile away from the cursor")
        _ = picker.stepWindowSwitcher(backwards: true)
        try expect(picker.switcherSelectionID == pickerOrder[1], "Reverse Tab continues from the pointer-selected card")
        try expect(!picker.switcherSelectionFromPointer, "Keyboard navigation restores automatic scrolling to selection")
        picker.selectWindowSwitcher(hovered)
        try expect(picker.removeSelectedWindowSwitcher(), "Remove the pointer-selected card from the switcher")
        try expect(!picker.cards.contains(where: { $0.id == hovered }) && !picker.switcherCards.contains(where: { $0.id == hovered }),
            "Taking a card out removes it from both board and centered switcher")
        try expect(picker.switcherSelectionID == pickerOrder[3], "Removal marks the next card in frozen visit order")
        try expect(picker.liveWindows.map(\.id) == pickerLive && picker.focusedID == pickerFocus,
            "Removing a card neither closes a native window nor activates another window")
        try expect(picker.folderState == pickerFolders && picker.removedCard?.1.id == hovered,
            "Removal preserves folder metadata and makes the exact card available to Undo")
        picker.undoRemove()
        try expect(picker.cards == pickerOriginals && picker.folderState == pickerFolders, "Undo restores original card order, name, pause and folder")
        picker.cancelWindowSwitcher()
        _ = picker.stepWindowSwitcher(backwards: false)
        let finalID = picker.switcherCards.last!.id
        let previousID = picker.switcherCards.dropLast().last!.id
        picker.selectWindowSwitcher(finalID)
        try expect(picker.removeSelectedWindowSwitcher() && picker.switcherSelectionID == previousID,
            "Removing the last tile selects the previous tile")
        picker.cancelWindowSwitcher()
        try expect(!picker.removeSelectedWindowSwitcher(), "A closed switcher has no removable selection")
        let single = BoardStore(preview: true)
        single.cards = [single.cards[0]]
        single.query = "Behold søket"
        _ = single.stepWindowSwitcher(backwards: false)
        try expect(single.removeSelectedWindowSwitcher() && single.switcherSelectionID == nil && single.switcherCards.isEmpty,
            "Removing the only card leaves no dangling selection")
        single.cancelWindowSwitcher()
        try expect(single.query == "Behold søket", "Closing after the last removal restores the board search")
        single.commitWindowSwitcher()
        try expect(single.cards.isEmpty, "Releasing Option after the last removal cannot reopen the removed card")
        let folderPicker = BoardStore(preview: true)
        let folderID = folderPicker.folderState.folders[0].id
        folderPicker.setSwitcherScope(.folder(folderID))
        let folderCards = folderPicker.cards
        let folderMetadata = folderPicker.folderState
        let removedFromFolder = folderPicker.switcherSelectionID!
        try expect(folderPicker.removeSelectedWindowSwitcher() && folderPicker.switcherScope == .folder(folderID),
            "Removing within a folder preserves the current folder filter")
        folderPicker.undoRemove()
        try expect(folderPicker.cards == folderCards && folderPicker.folderState == folderMetadata && folderPicker.cards.contains(where: { $0.id == removedFromFolder }),
            "Undo restores the exact removed card in its original folder")

        let diskBase = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDock-remove-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: diskBase) }
        let diskURL = diskBase.appendingPathComponent("board.json")
        let diskCards = Array(pickerOriginals.prefix(2))
        try BoardStorage.save(diskCards, to: diskURL)
        let diskStore = BoardStore(storageURL: diskURL, monitoring: false)
        try expect(diskStore.remove(diskCards[0].id), "Card removal persists without reading native windows")
        let afterRemoval = try BoardStorage.load(from: diskURL)
        try expect(afterRemoval == [diskCards[1]], "Removed card stays absent after restart")
        let beforeFailure = diskStore.cards
        let beforeUndo = diskStore.removedCard?.1
        let fakeLiveID = UUID()
        diskStore.permission = true
        diskStore.connections[diskCards[1].id] = fakeLiveID
        diskStore.switcherSelectionID = diskStore.windowSwitcher.step(candidates: [diskCards[1].id], current: nil, backwards: false)
        try FileManager.default.removeItem(at: diskURL)
        try FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: false)
        try expect(!diskStore.removeSelectedWindowSwitcher(), "A real write failure aborts switcher removal")
        try expect(diskStore.cards == beforeFailure && diskStore.switcherSelectionID == diskCards[1].id && diskStore.connections[diskCards[1].id] == fakeLiveID,
            "Failed removal preserves board, selection and native connection")
        try expect(diskStore.removedCard?.1 == beforeUndo && diskStore.message != nil, "Failed removal preserves the prior Undo and explains the failure")
        try FileManager.default.removeItem(at: diskURL)
        let corrupt = Data("broken board".utf8)
        try corrupt.write(to: diskURL)
        let damaged = BoardStore(storageURL: diskURL, monitoring: false)
        damaged.cards = diskCards
        try expect(!damaged.remove(diskCards[0].id) && damaged.cards == diskCards, "Damaged board data cannot be overwritten by removal")
        let corruptAfter = try Data(contentsOf: diskURL)
        try expect(corruptAfter == corrupt, "Damaged board bytes remain intact")
        print("PASS: \(checks) board integration checks")
    }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure.failed(message) }
        checks += 1
    }
    enum Failure: Error { case failed(String) }
}
