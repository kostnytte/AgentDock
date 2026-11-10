import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension AppDelegate {
    @objc func chooseApplicationShortcut() { chooseShortcut(kind: .application) }
    @objc func chooseFileShortcut() { chooseShortcut(kind: .file) }

    func chooseShortcut(kind: ShortcutKind, editingID: UUID? = nil) {
        if pinEditorPanel?.isVisible == true { pinEditorPanel?.makeKeyAndOrderFront(nil); return }
        if shortcutEditorPanel?.isVisible == true { shortcutEditorPanel?.makeKeyAndOrderFront(nil); return }
        hideBoard()
        closeWindowSearch()
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false, restoreFocus: false) }
        let picker = NSOpenPanel()
        picker.title = kind == .application ? "Velg app å feste" : "Velg fil å feste"
        picker.message = kind == .application ? "Appen kan være lukket. AgentDock starter den når du velger snarveien." : "Filen åpnes i standardappen når du velger snarveien."
        picker.prompt = kind == .application ? "Velg app" : "Velg fil"
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.treatsFilePackagesAsDirectories = false
        picker.resolvesAliases = true
        if kind == .application {
            picker.allowedContentTypes = [.applicationBundle]
            picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        }
        if let editingID, let old = store.shortcutState[editingID] { picker.directoryURL = URL(fileURLWithPath: old.path).deletingLastPathComponent() }
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = picker.url else { self.returnToBoard(); return }
            do {
                let target = try ShortcutSupport.makeTarget(url: url, kind: kind)
                let existingID = editingID ?? self.store.existingShortcut(for: target)?.id
                self.showShortcutEditor(target, existingID: existingID)
            } catch {
                self.store.message = error.localizedDescription
                self.returnToBoard()
            }
        }
    }
    func showShortcutEditor(_ target: ShortcutTarget, existingID: UUID?) {
        store.message = nil
        shortcutEditorTarget = target
        shortcutEditingID = existingID
        let panel = shortcutEditorPanel ?? workflowPanel(title: "AgentDock – fest app eller fil", size: NSSize(width: 440, height: 360))
        panel.contentView = NSHostingView(rootView: ShortcutEditor(store: store, target: target, existingID: existingID,
            save: { [weak self] name, folder in self?.saveShortcutEditor(name: name, folder: folder) },
            cancel: { [weak self] in self?.cancelShortcutEditor() }))
        shortcutEditorPanel = panel
        centerWorkflowPanel(panel)
    }
    func saveShortcutEditor(name: String, folder: UUID?) {
        guard let target = shortcutEditorTarget,
              store.saveShortcut(target, name: name, folder: folder, editingID: shortcutEditingID) != nil else { return }
        shortcutEditorPanel?.orderOut(nil)
        shortcutEditorTarget = nil
        shortcutEditingID = nil
        returnToBoard()
    }
    func cancelShortcutEditor() {
        shortcutEditorPanel?.orderOut(nil)
        shortcutEditorTarget = nil
        shortcutEditingID = nil
        store.message = nil
        returnToBoard()
    }
    func returnToBoard() {
        if let previewWindow { NSApp.activate(ignoringOtherApps: true); previewWindow.makeKeyAndOrderFront(nil) }
        else { showBoard() }
    }
}
