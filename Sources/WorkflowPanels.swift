import AppKit
import SwiftUI

extension AppDelegate {
    func workflowPanel(title: String, size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        return panel
    }
    func centerWorkflowPanel(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func showPinEditor(for window: LiveWindow) {
        guard pinEditorPanel?.isVisible != true else { pinEditorPanel?.makeKeyAndOrderFront(nil); return }
        pinReturnToSearch = searchPanel?.isVisible == true
        pinPreviousApplication = NSWorkspace.shared.frontmostApplication
        closeWindowSearch()
        hideBoard()
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false, restoreFocus: false) }
        store.message = nil
        pinEditorWindow = window
        let panel = pinEditorPanel ?? workflowPanel(title: "AgentDock – fest vindu", size: NSSize(width: 430, height: 360))
        panel.contentView = NSHostingView(rootView: WindowPinEditor(store: store, window: window,
            save: { [weak self] name, folder in self?.savePinEditor(name: name, folder: folder) },
            cancel: { [weak self] in self?.cancelPinEditor() }))
        pinEditorPanel = panel
        centerWorkflowPanel(panel)
    }
    func savePinEditor(name: String, folder: UUID?) {
        guard let window = pinEditorWindow, let id = store.savePinnedWindow(window, name: name, folder: folder),
              let card = store.cards.first(where: { $0.id == id }) else { return }
        pinEditorPanel?.orderOut(nil)
        pinEditorWindow = nil
        pinPreviousApplication = nil
        pinReturnToSearch = false
        quickPinFeedback.show(title: "Festet til AgentDock", detail: card.name, success: true)
        store.focus(card)
    }
    func cancelPinEditor() {
        pinEditorPanel?.orderOut(nil)
        pinEditorWindow = nil
        let returnToSearch = pinReturnToSearch
        let previous = pinPreviousApplication
        pinReturnToSearch = false
        pinPreviousApplication = nil
        store.message = nil
        if returnToSearch { showWindowSearch(reset: false) }
        else if NSApp.isActive, let previous, previous.processIdentifier != getpid() { previous.activate(options: []) }
    }

    @objc func showWindowSearchAction() { showWindowSearch() }
    func showWindowSearch(reset: Bool = true) {
        guard pinEditorPanel?.isVisible != true else { pinEditorPanel?.makeKeyAndOrderFront(nil); return }
        hideBoard()
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false, restoreFocus: false) }
        if reset { store.windowSearchQuery = ""; store.searchSelectionID = nil }
        let panel = searchPanel ?? workflowPanel(title: "AgentDock – alle åpne vinduer", size: NSSize(width: 620, height: 560))
        if searchPanel == nil {
            panel.contentView = NSHostingView(rootView: WindowSearchView(store: store,
                pin: { [weak self] in self?.showPinEditor(for: $0) }, close: { [weak self] in self?.closeWindowSearch() }))
            searchPanel = panel
        }
        store.windowSearchActive = true
        store.refresh(discover: true)
        centerWorkflowPanel(panel)
    }
    func closeWindowSearch() { store.windowSearchActive = false; searchPanel?.orderOut(nil) }

    @objc func showArchive() {
        guard pinEditorPanel?.isVisible != true else { pinEditorPanel?.makeKeyAndOrderFront(nil); return }
        hideBoard()
        closeWindowSearch()
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false, restoreFocus: false) }
        store.message = nil
        let panel = archivePanel ?? workflowPanel(title: "AgentDock – rydd opp og arkiv", size: NSSize(width: 620, height: 570))
        if archivePanel == nil {
            panel.contentView = NSHostingView(rootView: ArchiveView(store: store, close: { [weak self] in self?.archivePanel?.orderOut(nil) }))
            archivePanel = panel
        }
        store.refresh(discover: true)
        centerWorkflowPanel(panel)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == shortcutEditorPanel { cancelShortcutEditor(); return false }
        if sender == pinEditorPanel { cancelPinEditor(); return false }
        if sender == searchPanel { closeWindowSearch(); return false }
        return true
    }
}
