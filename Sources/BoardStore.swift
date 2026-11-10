import AppKit
import SwiftUI
import ApplicationServices

final class BoardStore: ObservableObject {
    @Published var cards: [WindowCard] = []
    @Published var liveWindows: [LiveWindow] = []
    @Published var connections: [UUID: UUID] = [:]
    @Published var permission = false
    @Published var focusedID: UUID?
    @Published var query = ""
    @Published var message: String?
    @Published var storageError: String?
    @Published var loading = false
    var discovering = false
    @Published var compact = true
    @Published var pinStatus: String?
    @Published var draggingID: UUID?
    private var cardDragToken: UUID?
    @Published var removedCard: (Int, WindowCard)?
    @Published var folderState = FolderState()
    @Published var folderStorageError: String?
    @Published var folderUndo: FolderState?
    @Published var switcherSelectionID: UUID?
    @Published var keyboardSelection: BoardNavigationItem?
    @Published var pausedExpanded = true
    @Published var archiveState = ArchiveState()
    @Published var archiveStorageError: String?
    @Published var archiveUndo: ArchiveState?
    @Published var shortcutState = ShortcutState()
    @Published var shortcutStorageError: String?
    @Published var launchingShortcutID: UUID?
    var shortcutOpenRequest = UUID()
    var shortcutOpener: ((ShortcutTarget, URL, @escaping (Bool, String?) -> Void) -> Void)?
    @Published var switcherScope: WindowScope = .all
    @Published var windowSearchQuery = ""
    @Published var searchSelectionID: UUID?
    var windowSearchActive = false
    var windowSwitcher = WindowSwitcherState()
    var switcherSelectionFromPointer = false
    var switcherSavedQuery: String?
    let preview: Bool
    let storageURL: URL
    var foldersURL: URL { storageURL.deletingLastPathComponent().appendingPathComponent("folders.json") }
    private var timer: Timer?
    private var refreshCount = 0
    private var scanning = false
    private var pendingDiscovery = false
    private let scanQueue = DispatchQueue(label: "local.agentdock.window-scan", qos: .userInitiated)
    var windowChosen: (() -> Void)?
    var focusFailed: (() -> Void)?
    private var focusRequest = UUID()
    var compactChanged: ((Bool) -> Void)?

    init(preview: Bool = false, storageURL: URL? = nil, monitoring: Bool = true) {
        self.preview = preview
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentDock/board.json")
        if preview {
            permission = true
            cards = [
                WindowCard(bundleID: "com.anthropic.claudefordesktop", appName: "Claude", windowTitle: "Sparring og ideer", name: "Min faste sparringspartner", project: "Hver dag", lastVisited: Date()),
                WindowCard(bundleID: "com.openai.codex", appName: "Codex", windowTitle: "Forbedre onboarding", name: "Onboarding", project: "Praksis", lastVisited: Date().addingTimeInterval(-240)),
                WindowCard(bundleID: "com.openai.codex", appName: "Codex", windowTitle: "Jobbe med API", name: "API og integrasjoner", project: "Praksis", lastVisited: Date().addingTimeInterval(-600)),
                WindowCard(bundleID: "com.openai.codex", appName: "Codex", windowTitle: "AgentDock", name: "Denne lille appen", project: "AgentDock", lastVisited: Date().addingTimeInterval(-60)),
                WindowCard(bundleID: "com.praksis.desktop", appName: "Praksis", windowTitle: "Praksis Desktop", name: "Testmiljøet mitt", project: "Praksis"),
                WindowCard(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Research", name: "Research og referanser", project: "Arbeidsrom"),
                WindowCard(bundleID: "com.openai.codex", appName: "Codex", windowTitle: "Refaktorering", name: "Rydding i kodebasen", project: "Senere", paused: true),
                WindowCard(bundleID: "com.openai.codex", appName: "Codex", windowTitle: "Eksperiment", name: "En idé til senere", paused: true)
            ]
            focusedID = cards[3].id
            let customers = WindowFolder(name: "Kunder")
            folderState.folders = [customers]
            folderState.assign(cards[1].id, to: customers.id)
            folderState.assign(cards[2].id, to: customers.id)
            liveWindows = cards.enumerated().map { index, card in
                let pid = pid_t(70000 + index)
                return LiveWindow(id: UUID(), element: AXUIElementCreateApplication(pid), pid: pid,
                    bundleID: card.bundleID, appName: card.appName, title: card.windowTitle)
            }
            for (card, live) in zip(cards, liveWindows) { connections[card.id] = live.id }
            let pid: pid_t = 70100
            liveWindows.append(LiveWindow(id: UUID(), element: AXUIElementCreateApplication(pid), pid: pid,
                bundleID: "com.apple.TextEdit", appName: "TextEdit", title: "Notater fra kundemøte"))
        } else {
            compact = UserDefaults.standard.object(forKey: "compact") as? Bool ?? true
            do { cards = try BoardStorage.load(from: self.storageURL) }
            catch { storageError = "Oversikten kunne ikke leses. Den gamle filen blir bevart. \(error.localizedDescription)" }
            do { folderState = try FolderStorage.load(from: foldersURL) }
            catch { folderStorageError = "Mappene kunne ikke leses. Mappefilen er bevart; vinduskortene kan fortsatt brukes." }
            do { archiveState = try ArchiveStorage.load(from: archiveURL) }
            catch { archiveStorageError = "Arkivet kunne ikke leses. Filen er bevart; arkivering er midlertidig deaktivert." }
            do { shortcutState = try ShortcutStorage.load(from: shortcutsURL) }
            catch { shortcutStorageError = "Snarveiene kunne ikke leses. Filen er bevart; vinduskortene kan fortsatt brukes." }
            if monitoring {
                permission = WindowAccess.trusted
                timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
                refresh()
            }
        }
    }

    private func matching(paused: Bool) -> [WindowCard] {
        let matched = Set(BoardStorage.matching(cards, query: query, paused: paused).map(\.id))
        let folderMatches = Set(folderState.folders.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.id))
        return cards.filter { card in
            !isArchived(card.id) && card.paused == paused && (matched.contains(card.id) ||
                (folderState.folderID(for: card.id).map { folderMatches.contains($0) } ?? false))
        }
    }
    var active: [WindowCard] { matching(paused: false) }
    var paused: [WindowCard] { matching(paused: true) }
    var unfiledActive: [WindowCard] { active.filter { folderState.folderID(for: $0.id) == nil } }
    var visibleFolders: [WindowFolder] {
        let matches = Set((active + paused).map(\.id))
        return folderState.folders.filter { folder in
            query.isEmpty || folder.name.localizedCaseInsensitiveContains(query) ||
                cards.contains { matches.contains($0.id) && folderState.folderID(for: $0.id) == folder.id }
        }
    }
    func folderName(for card: WindowCard) -> String? {
        guard let id = folderState.folderID(for: card.id) else { return nil }
        return folderState.folders.first { $0.id == id }?.name
    }
    func connected(_ card: WindowCard) -> Bool {
        if let target = shortcut(for: card) { return preview || ShortcutSupport.resolvedURL(target) != nil }
        return preview || (permission && connections[card.id] != nil)
    }

    @discardableResult private func updateFolders(_ next: FolderState) -> Bool {
        guard folderStorageError == nil else { message = folderStorageError; return false }
        do { if !preview { try FolderStorage.save(next, to: foldersURL) } }
        catch { message = "Mappen kunne ikke lagres: \(error.localizedDescription)"; return false }
        folderState = next
        folderUndo = nil
        return true
    }

    func saveFolder(id: UUID?, name: String, cards selected: Set<UUID>) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !folderState.folders.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else { return false }
        var next = folderState
        let folderID: UUID
        if let id, let index = next.folders.firstIndex(where: { $0.id == id }) {
            next.folders[index].name = clean
            folderID = id
        } else {
            let folder = WindowFolder(name: clean)
            folderID = folder.id
            next.folders.append(folder)
        }
        for card in cards where !isArchived(card.id) {
            if selected.contains(card.id) { next.assign(card.id, to: folderID) }
            else if next.folderID(for: card.id) == folderID { next.assign(card.id, to: nil) }
        }
        return updateFolders(next)
    }

    @discardableResult func moveCard(_ cardID: UUID, to folderID: UUID?) -> Bool {
        guard cards.contains(where: { $0.id == cardID }),
              folderID == nil || folderState.folders.contains(where: { $0.id == folderID }) else { return false }
        var next = folderState
        next.assign(cardID, to: folderID)
        return updateFolders(next)
    }

    func beginCardDrag(_ id: UUID) -> String {
        let token = UUID()
        draggingID = id
        cardDragToken = token
        UserDefaults.standard.set(["event": "began", "time": Date().timeIntervalSince1970] as [String: Any], forKey: "RuntimeDragState")
        return "agentdock-card:\(token.uuidString):\(id.uuidString)"
    }

    func cancelCardDrag() {
        draggingID = nil
        cardDragToken = nil
        UserDefaults.standard.set(["event": "cancelled", "time": Date().timeIntervalSince1970] as [String: Any], forKey: "RuntimeDragState")
    }

    func acceptsCardDrag(_ payload: String) -> Bool {
        guard let source = draggingID, let token = cardDragToken, cards.contains(where: { $0.id == source }) else { return false }
        return payload == "agentdock-card:\(token.uuidString):\(source.uuidString)"
    }

    @discardableResult func completeCardDrop(_ payload: String, to folder: UUID?, before target: UUID? = nil) -> Bool {
        guard acceptsCardDrag(payload), let source = draggingID else { return false }
        defer { draggingID = nil; cardDragToken = nil }
        if let target {
            guard let from = cards.first(where: { $0.id == source }),
                  let to = cards.first(where: { $0.id == target }), from.paused == to.paused,
                  folderState.folderID(for: source) == folderState.folderID(for: target) else { return false }
            move(source, before: target)
            return true
        }
        guard moveCard(source, to: folder) else { return false }
        if let folder, let index = folderState.folders.firstIndex(where: { $0.id == folder }), !folderState.folders[index].expanded {
            var next = folderState
            next.folders[index].expanded = true
            _ = updateFolders(next)
        }
        keyboardSelection = cards.first(where: { $0.id == source })?.paused == true ? .pausedSection : .window(source)
        UserDefaults.standard.set(["event": "filed", "time": Date().timeIntervalSince1970] as [String: Any], forKey: "RuntimeDragState")
        return true
    }

    func toggleFolder(_ id: UUID) {
        keyboardSelection = .folder(id)
        var next = folderState
        guard let index = next.folders.firstIndex(where: { $0.id == id }) else { return }
        next.folders[index].expanded.toggle()
        _ = updateFolders(next)
    }

    func dissolveFolder(_ id: UUID) {
        let old = folderState
        var next = old
        next.dissolve(id)
        if updateFolders(next) { folderUndo = old }
    }

    func undoDissolveFolder() {
        guard let old = folderUndo else { return }
        _ = updateFolders(old)
    }

    @discardableResult func stepWindowSwitcher(backwards: Bool) -> Bool {
        switcherSelectionFromPointer = false
        if switcherSavedQuery == nil { switcherSavedQuery = query; query = "" }
        let candidates = switcherCandidateIDs
        var current = focusedID
        if !preview {
            current = nil
            if let focused = WindowAccess.focusedWindow(), let live = liveWindows.first(where: { CFEqual($0.element, focused) }) {
                current = connections.first(where: { $0.value == live.id })?.key
            }
        }
        switcherSelectionID = windowSwitcher.step(candidates: candidates, current: current, backwards: backwards)
        // An empty folder is explained in the switcher itself, not as a stale
        // warning in the menubar board.
        return switcherSelectionID != nil
    }

    var switcherCards: [WindowCard] {
        windowSwitcher.order.compactMap { id in cards.first { $0.id == id && !$0.paused && !isArchived($0.id) && connected($0) } }
    }

    func selectWindowSwitcher(_ id: UUID, fromPointer: Bool = false) {
        guard switcherSelectionID != id, switcherCards.contains(where: { $0.id == id }) else { return }
        switcherSelectionFromPointer = fromPointer
        windowSwitcher.select(id)
        switcherSelectionID = id
    }

    @discardableResult func removeSelectedWindowSwitcher() -> Bool {
        let visible = switcherCards
        guard let id = switcherSelectionID, let index = visible.firstIndex(where: { $0.id == id }), remove(id) else { return false }
        windowSwitcher.remove(id)
        let remaining = visible.filter { $0.id != id }
        if remaining.isEmpty { switcherSelectionID = nil }
        else { selectWindowSwitcher(remaining[min(index, remaining.count - 1)].id) }
        return true
    }

    func cancelWindowSwitcher() {
        switcherSelectionFromPointer = false
        switcherSelectionID = nil
        windowSwitcher.reset()
        if let saved = switcherSavedQuery { query = saved; switcherSavedQuery = nil }
    }
    func commitWindowSwitcher() {
        let id = switcherSelectionID
        cancelWindowSwitcher()
        guard let card = cards.first(where: { $0.id == id && !$0.paused && !isArchived($0.id) }), connected(card) else { return }
        focus(card)
    }

    var navigationRows: [BoardNavigationItem] {
        BoardNavigation.rows(active: active, paused: paused, folders: visibleFolders, state: folderState,
            searching: !query.isEmpty, pausedExpanded: pausedExpanded,
            forcedFolder: switcherSelectionID.flatMap { folderState.folderID(for: $0) })
    }

    private var currentNavigationItem: BoardNavigationItem? {
        let rows = navigationRows
        if let selection = keyboardSelection, rows.contains(selection) { return selection }
        if let focusedID {
            if rows.contains(.window(focusedID)) { return .window(focusedID) }
            if let folder = folderState.folderID(for: focusedID), rows.contains(.folder(folder)) { return .folder(folder) }
        }
        return nil
    }

    func moveKeyboardSelection(_ delta: Int) {
        keyboardSelection = BoardNavigation.moved(in: navigationRows, from: currentNavigationItem, delta: delta)
    }

    func expandKeyboardSelection() {
        guard let selected = currentNavigationItem ?? navigationRows.first else { return }
        keyboardSelection = selected
        switch selected {
        case .folder(let id):
            guard let folder = folderState.folders.first(where: { $0.id == id }) else { return }
            if !folder.expanded { toggleFolder(id) }
            else if let first = active.first(where: { folderState.folderID(for: $0.id) == id }) { keyboardSelection = .window(first.id) }
        case .pausedSection:
            if !pausedExpanded { pausedExpanded = true }
            else if let first = paused.first { keyboardSelection = .window(first.id) }
        case .window: break
        }
    }

    func collapseKeyboardSelection() {
        guard let selected = currentNavigationItem ?? navigationRows.first else { return }
        keyboardSelection = selected
        switch selected {
        case .folder(let id):
            if folderState.folders.first(where: { $0.id == id })?.expanded == true { toggleFolder(id) }
        case .pausedSection: pausedExpanded = false
        case .window(let id):
            if cards.first(where: { $0.id == id })?.paused == true { keyboardSelection = .pausedSection }
            else if let folder = folderState.folderID(for: id) { keyboardSelection = .folder(folder) }
        }
    }

    func activateKeyboardSelection() {
        let rows = navigationRows
        let selected = currentNavigationItem ?? rows.first
        guard let selected else { return }
        keyboardSelection = selected
        switch selected {
        case .window(let id): if let card = cards.first(where: { $0.id == id }) { focus(card) }
        case .folder(let id): toggleFolder(id)
        case .pausedSection: pausedExpanded.toggle()
        }
    }

    func save() {
        guard !preview else { return }
        // A failed read must never silently overwrite the user's original board.
        guard storageError == nil else { return }
        do { try BoardStorage.save(cards, to: storageURL) }
        catch { message = "Endringen kunne ikke lagres: \(error.localizedDescription)" }
    }

    func tick() {
        let access = WindowAccess.trusted
        if permission != access { permission = access; if access { refresh() } }
        guard access else { focusedID = nil; return }
        if let focused = WindowAccess.focusedWindow(), let live = liveWindows.first(where: { CFEqual($0.element, focused) }),
           let id = connections.first(where: { $0.value == live.id })?.key {
            if focusedID != id {
                focusedID = id
                if let index = cards.firstIndex(where: { $0.id == id }) { cards[index].lastVisited = Date(); save() }
            }
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() { focusedID = nil }
        refreshCount += 1
        if refreshCount % 3 == 0 { refresh(discover: discovering || windowSearchActive) }
    }

    func refresh(discover: Bool = false) {
        guard !preview else { return }
        permission = WindowAccess.trusted
        guard permission else { return }
        if scanning { if discover { pendingDiscovery = true }; return }
        scanning = true
        loading = discover
        let bundles = Set(cards.filter { !isShortcut($0.id) }.map(\.bundleID))
        let apps = NSWorkspace.shared.runningApplications.filter { discover || bundles.contains($0.bundleIdentifier ?? "") }
        let previous = liveWindows
        scanQueue.async { [weak self] in
            let result = WindowAccess.windows(applications: apps, previous: previous)
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                self.loading = false
                self.reconcile(result)
                if self.pendingDiscovery {
                    self.pendingDiscovery = false
                    self.refresh(discover: true)
                }
            }
        }
    }

    private func reconcile(_ result: [LiveWindow]) {
        liveWindows = result
        var updated: [UUID: UUID] = [:]
        var used = Set<Int>()
        var changed = false
        // Keep the actual remote window identity when a conversation title changes.
        for index in cards.indices where !isShortcut(cards[index].id) {
            if let liveID = connections[cards[index].id], let n = result.firstIndex(where: { $0.id == liveID }) {
                updated[cards[index].id] = liveID
                used.insert(n)
                if cards[index].windowTitle != result[n].title { cards[index].windowTitle = result[n].title; changed = true }
            }
        }
        let identities = result.map { WindowIdentity(bundleID: $0.bundleID, title: $0.title) }
        let pending = cards.filter { !isShortcut($0.id) && updated[$0.id] == nil }
        for card in pending {
            if let index = uniqueMatch(for: card, candidates: identities, used: used, pendingCards: pending) {
                updated[card.id] = result[index].id
                used.insert(index)
            }
        }
        connections = updated
        if changed { save() }
    }

    func contains(_ window: LiveWindow) -> Bool { connections.values.contains(window.id) }

    @discardableResult func pin(_ window: LiveWindow) -> Bool {
        if let existing = liveWindows.first(where: { $0.pid == window.pid && CFEqual($0.element, window.element) }),
           let cardID = connections.first(where: { $0.value == existing.id })?.key,
           let index = cards.firstIndex(where: { $0.id == cardID }) {
            if isArchived(cardID), !restoreArchived([cardID]) { return false }
            if cards[index].paused { cards[index].paused = false; save() }
            return false
        }
        let matching = liveWindows.first(where: { $0.pid == window.pid && CFEqual($0.element, window.element) }) ?? window
        if !liveWindows.contains(where: { $0.id == matching.id }) { liveWindows.append(matching) }
        add(matching)
        return true
    }

    func add(_ window: LiveWindow) {
        guard !contains(window) else { return }
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = WindowCard(bundleID: window.bundleID, appName: window.appName, windowTitle: window.title,
            name: title.isEmpty ? window.appName : title)
        cards.append(card)
        connections[card.id] = window.id
        save()
    }

    func focus(_ card: WindowCard) {
        keyboardSelection = .window(card.id)
        guard !preview else { focusedID = card.id; return }
        if let target = shortcut(for: card) { openShortcut(card, target: target); return }
        permission = WindowAccess.trusted
        // The inline access row already explains this. Clicking a saved card
        // must never produce a repeated modal alert or a macOS permission prompt.
        guard permission else { return }
        guard let liveID = connections[card.id], let window = liveWindows.first(where: { $0.id == liveID }) else {
            message = "Vinduet er ikke tilgjengelig. Åpne det i \(card.appName), og hent vinduer på nytt. Kortet ditt er bevart."
            return
        }
        let request = UUID()
        focusRequest = request
        message = nil
        windowChosen?()
        WindowAccess.focus(window) { [weak self] success in
            guard let self, self.focusRequest == request else { return }
            if success {
                self.focusedID = card.id
                if let index = self.cards.firstIndex(where: { $0.id == card.id }) { self.cards[index].lastVisited = Date(); self.save() }
            } else {
                self.message = "Vinduet i \(card.appName) kunne ikke hentes frem. Kortet er bevart."
                self.focusFailed?()
            }
        }
    }

    func togglePause(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].paused.toggle()
        save()
    }

    func edit(_ id: UUID, name: String, project: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        cards[index].name = clean
        cards[index].project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    @discardableResult func remove(_ id: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return false }
        guard storageError == nil else { message = storageError; return false }
        var next = cards
        let card = next.remove(at: index)
        if !preview {
            do { try BoardStorage.save(next, to: storageURL) }
            catch { message = "Kortet kunne ikke tas ut: \(error.localizedDescription)"; return false }
        }
        removedCard = (index, card)
        cards = next
        connections.removeValue(forKey: id)
        message = nil
        return true
    }

    func undoRemove() {
        guard let (index, card) = removedCard else { return }
        cards.insert(card, at: min(index, cards.count))
        removedCard = nil
        save()
        refresh()
    }

    func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = cards.firstIndex(where: { $0.id == id }),
              let destination = cards.firstIndex(where: { $0.id == target }), cards[from].paused == cards[destination].paused,
              folderState.folderID(for: id) == folderState.folderID(for: target) else { return }
        let item = cards.remove(at: from)
        cards.insert(item, at: min(destination, cards.count))
        save()
    }

    func jump(_ number: Int) {
        // Shortcuts always follow the unfiltered active board, never the paused tray.
        let items = cards.filter { !$0.paused && !isArchived($0.id) }
        guard items.indices.contains(number - 1) else { return }
        focus(items[number - 1])
    }
}
