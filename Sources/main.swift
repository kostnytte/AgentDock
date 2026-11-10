import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    var store: BoardStore!
    var popover: NSPopover!
    var dropAnchor: NSWindow!
    var status: NSStatusItem!
    var hotKeys: [EventHotKeyRef] = []
    var handler: EventHandlerRef?
    var pinTracker: WindowPinTracker?
    var switcherTimer: Timer?
    var switcherPanel: WindowSwitcherPanel?
    var switcherPreviousApplication: NSRunningApplication?
    var previewWindow: NSWindow?
    var localKeyMonitor: Any?
    let quickPinFeedback = QuickPinFeedback()
    var pinEditorPanel: NSPanel?
    var pinEditorWindow: LiveWindow?
    var pinPreviousApplication: NSRunningApplication?
    var pinReturnToSearch = false
    var searchPanel: NSPanel?
    var archivePanel: NSPanel?
    var shortcutEditorPanel: NSPanel?
    var shortcutEditorTarget: ShortcutTarget?
    var shortcutEditingID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let arguments = CommandLine.arguments
        let preview = arguments.contains("--preview") || (Bundle.main.object(forInfoDictionaryKey: "AgentDockPreview") as? Bool == true)
        store = BoardStore(preview: preview)
        let hosting = NSHostingView(rootView: BoardView(store: store))
        hosting.sizingOptions = []
        let controller = NSViewController()
        controller.view = hosting
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = controller
        // This window is never shown. It only remembers the screen rectangle
        // where the temporary drop target belongs after the popover closes.
        dropAnchor = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        resizeBoard(compact: store.compact)
        store.windowChosen = { [weak self] in self?.hideBoard(); self?.closeWindowSearch() }
        store.focusFailed = { [weak self] in self?.showBoard() }
        store.compactChanged = { [weak self] compact in
            UserDefaults.standard.set(compact, forKey: "compact")
            self?.resizeBoard(compact: compact)
        }
        createMenu()
        createStatusItem()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // App-directed key events can bypass Carbon (for example assistive
            // input). A physical registered hotkey is consumed by Carbon, so
            // it does not also arrive through this fallback.
            if Int(event.keyCode) == kVK_Tab, event.modifierFlags.contains(.option),
               event.modifierFlags.intersection([.command, .control]).isEmpty {
                self.beginWindowSwitcher(backwards: event.modifierFlags.contains(.shift))
                return nil
            }
            if event.window == self.searchPanel, self.searchPanel?.isVisible == true,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                guard (event.window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
                switch Int(event.keyCode) {
                case kVK_UpArrow: self.store.moveSearchSelection(-1)
                case kVK_DownArrow: self.store.moveSearchSelection(1)
                case kVK_Return, kVK_ANSI_KeypadEnter: self.store.openSearchSelection()
                case kVK_Escape: self.closeWindowSearch()
                default: return event
                }
                return nil
            }
            if self.switcherPanel?.isVisible == true, event.window == self.switcherPanel {
                if Int(event.keyCode) == kVK_ANSI_Q, event.modifierFlags.contains(.option),
                   event.modifierFlags.intersection([.command, .control, .shift]).isEmpty {
                    if !event.isARepeat {
                        _ = self.store.removeSelectedWindowSwitcher()
                    }
                    return nil
                }
                switch Int(event.keyCode) {
                case kVK_Escape: self.dismissWindowSwitcher(commit: false)
                case kVK_LeftArrow: _ = self.store.stepWindowSwitcher(backwards: true)
                case kVK_RightArrow: _ = self.store.stepWindowSwitcher(backwards: false)
                case kVK_UpArrow: self.store.cycleSwitcherScope(-1)
                case kVK_DownArrow: self.store.cycleSwitcherScope(1)
                case kVK_Return, kVK_ANSI_KeypadEnter: self.dismissWindowSwitcher(commit: true)
                case kVK_Tab:
                    _ = self.store.stepWindowSwitcher(backwards: event.modifierFlags.contains(.shift))
                default: return event
                }
                return nil
            }
            guard let window = event.window,
                  window == self.popover.contentViewController?.view.window || window == self.previewWindow,
                  window.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  !self.store.navigationRows.isEmpty else { return event }
            let editor = window.firstResponder as? NSTextView
            guard editor?.hasMarkedText() != true else { return event }
            switch Int(event.keyCode) {
            case kVK_UpArrow:
                if editor?.isEditable == true { window.makeFirstResponder(nil) }
                self.store.moveKeyboardSelection(-1)
            case kVK_DownArrow:
                if editor?.isEditable == true { window.makeFirstResponder(nil) }
                self.store.moveKeyboardSelection(1)
            case kVK_RightArrow:
                if editor?.isEditable == true { return event }
                self.store.expandKeyboardSelection()
            case kVK_LeftArrow:
                if editor?.isEditable == true { return event }
                self.store.collapseKeyboardSelection()
            case kVK_Return, kVK_ANSI_KeypadEnter: self.store.activateKeyboardSelection()
            default: return event
            }
            return nil
        }
        if !preview {
            registerHotKeys()
            pinTracker = WindowPinTracker(board: dropAnchor, store: store, onPin: { [weak self] in self?.showBoard() })
        }
        if Bundle.main.object(forInfoDictionaryKey: "AgentDockSwitcherPreview") as? Bool == true {
            _ = store.stepWindowSwitcher(backwards: false)
            presentWindowSwitcher()
        } else if preview && Bundle.main.object(forInfoDictionaryKey: "AgentDockPreview") as? Bool == true {
            // Isolated visual QA: synthetic cards, no window access or hotkeys,
            // and a normal preview window independent of menu-bar visibility.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 650),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "AgentDock – forhåndsvisning"
            window.contentView = hosting
            window.center()
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
        } else { showBoard() }
        if preview, let index = arguments.firstIndex(of: "--preview"), arguments.indices.contains(index + 1) {
            let destination = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let view = self?.popover.contentViewController?.view,
                      let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
                view.cacheDisplay(in: view.bounds, to: image)
                if let data = image.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: destination)) }
                NSApp.terminate(nil)
            }
        }
    }

    func resizeBoard(compact: Bool) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = compact ? 350 : 740
        let height = min(compact ? 650 : 760, frame.height - 70)
        popover.contentSize = NSSize(width: width, height: height)
        popover.contentViewController?.view.setFrameSize(popover.contentSize)
        dropAnchor.setFrame(NSRect(x: frame.maxX - width - 16, y: frame.maxY - height - 16, width: width, height: height), display: false)
    }

    func createMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(withTitle: "Om AgentDock", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Vis settekassen", action: #selector(showBoard), keyEquivalent: "0")
        menu.addItem(withTitle: "Vis vindusvelger", action: #selector(showWindowSwitcher), keyEquivalent: "")
        menu.addItem(withTitle: "Søk i alle åpne vinduer", action: #selector(showWindowSearchAction), keyEquivalent: "")
        menu.addItem(withTitle: "Rydd opp og arkiv", action: #selector(showArchive), keyEquivalent: "")
        menu.addItem(withTitle: "Fest app …", action: #selector(chooseApplicationShortcut), keyEquivalent: "")
        menu.addItem(withTitle: "Fest fil …", action: #selector(chooseFileShortcut), keyEquivalent: "")
        menu.addItem(withTitle: "Avslutt AgentDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        root.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Rediger")
        edit.addItem(withTitle: "Klipp ut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Lim inn", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Marker alt", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        root.addItem(editItem)
        NSApp.mainMenu = root
    }

    func createStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "AgentDock")
        status.button?.target = self
        status.button?.action = #selector(toggleBoard)
        status.button?.toolTip = "AgentDock · ⌃⌥Mellomrom"
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "AgentDock", .applicationVersion: "0.11 · lokal prototype",
            .credits: NSAttributedString(string: "En settekasse for arbeidsvinduene dine.\nPause endrer bare oversikten.\nIngen innholdslesing, skjermopptak eller nettverkstjeneste.")])
    }
    @objc func showBoard() {
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false, restoreFocus: false) }
        guard let button = status.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
        if let frame = popover.contentViewController?.view.window?.frame { dropAnchor.setFrame(frame, display: false) }
        recordWindowState("shown")
    }
    func hideBoard() {
        if popover.isShown { popover.performClose(nil) }
        recordWindowState("hidden")
    }
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.title = "AgentDock"
        recordWindowState("shown")
    }
    func popoverDidClose(_ notification: Notification) {
        // The menubar board and centered switcher have separate lifecycles.
        recordWindowState("hidden")
    }
    func applicationDidResignActive(_ notification: Notification) {
        hideBoard()
        if switcherPanel?.isVisible == true { dismissWindowSwitcher(commit: false) }
    }
    private func recordWindowState(_ event: String) {
        guard popover != nil else { return }
        UserDefaults.standard.set(["event": event, "visible": popover.isShown,
            "active": NSApp.isActive, "pid": Int(getpid()), "time": Date().timeIntervalSince1970,
            "presentation": "transientPopover"] as [String: Any], forKey: "RuntimeWindowState")
        UserDefaults.standard.synchronize()
    }
    @objc func toggleBoard() {
        if popover.isShown { hideBoard() } else { showBoard() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showBoard(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showWindowSwitcher() {
        if switcherPanel?.isVisible == true { return }
        switcherPreviousApplication = NSWorkspace.shared.frontmostApplication
        hideBoard()
        _ = store.stepWindowSwitcher(backwards: false)
        presentWindowSwitcher()
    }

    func beginWindowSwitcher(backwards: Bool) {
        // Capture before activating our own panel, and only once per gesture.
        if switcherPanel?.isVisible != true { switcherPreviousApplication = NSWorkspace.shared.frontmostApplication }
        // Hide the dock first; it is never the UI for the global gesture.
        hideBoard()
        _ = store.stepWindowSwitcher(backwards: backwards)
        if switcherPanel?.isVisible != true { presentWindowSwitcher() }
        guard switcherTimer == nil else { return }
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if !NSEvent.modifierFlags.contains(.option) { self.dismissWindowSwitcher(commit: true) }
        }
        switcherTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func presentWindowSwitcher() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(620, CGFloat(store.switcherCards.count) * 120 + 36), min(1120, frame.width - 48))
        let size = NSSize(width: width, height: 295)
        let panel = switcherPanel ?? WindowSwitcherPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        if switcherPanel == nil {
            panel.title = "AgentDock – vindusvelger"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.acceptsMouseMovedEvents = true
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentView = NSHostingView(rootView: WindowSwitcherView(store: store) { [weak self] id in
                self?.store.selectWindowSwitcher(id)
                self?.dismissWindowSwitcher(commit: true)
            })
            switcherPanel = panel
        }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
            width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        recordSwitcherState("shown")
    }

    private func recordSwitcherState(_ event: String) {
        guard let panel = switcherPanel else { return }
        UserDefaults.standard.set(["event": event, "visible": panel.isVisible,
            "pid": Int(getpid()), "time": Date().timeIntervalSince1970,
            "presentation": "centeredSwitcher", "windows": store.switcherCards.count,
            "x": panel.frame.origin.x, "y": panel.frame.origin.y,
            "width": panel.frame.width, "height": panel.frame.height] as [String: Any], forKey: "RuntimeSwitcherState")
        UserDefaults.standard.synchronize()
    }

    func dismissWindowSwitcher(commit: Bool, restoreFocus: Bool = true) {
        let shouldCommit = commit && store.switcherSelectionID != nil
        let previous = switcherPreviousApplication
        switcherPreviousApplication = nil
        switcherTimer?.invalidate()
        switcherTimer = nil
        switcherPanel?.orderOut(nil)
        recordSwitcherState(shouldCommit ? "committed" : "cancelled")
        if shouldCommit { store.commitWindowSwitcher() }
        else {
            store.cancelWindowSwitcher()
            if restoreFocus, NSApp.isActive, let previous, previous.processIdentifier != getpid() {
                previous.activate(options: [])
            }
        }
    }

    func registerHotKeys() {
        var registration: [String: Int32] = [:]
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard error == noErr else { return error }
            DispatchQueue.main.async {
                switch id.id {
                case 0: AppDelegate.shared.toggleBoard()
                case 10: AppDelegate.shared.beginWindowSwitcher(backwards: false)
                case 11: AppDelegate.shared.beginWindowSwitcher(backwards: true)
                case 12: AppDelegate.shared.pinActiveWindow()
                case 13: AppDelegate.shared.showWindowSearchAction()
                default: AppDelegate.shared.store.jump(Int(id.id))
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        let keys: [Int] = [kVK_Space, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, code) in keys.enumerated() {
            var reference: EventHotKeyRef?
            let error = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey),
                EventHotKeyID(signature: 0x41444F43, id: UInt32(index)), GetApplicationEventTarget(), 0, &reference)
            registration[index == 0 ? "showBoard" : "window\(index)"] = error
            if error == noErr, let reference { hotKeys.append(reference) }
            else { store.message = "En hurtigtast er allerede i bruk. Du kan bruke kortene og menylinjeikonet. (⌃⌥\(index == 0 ? "Mellomrom" : String(index)))" }
        }
        for (id, modifiers) in [(UInt32(10), UInt32(optionKey)), (UInt32(11), UInt32(optionKey | shiftKey))] {
            var reference: EventHotKeyRef?
            let error = RegisterEventHotKey(UInt32(kVK_Tab), modifiers,
                EventHotKeyID(signature: 0x41444F43, id: id), GetApplicationEventTarget(), 0, &reference)
            registration[id == 10 ? "optionTab" : "optionShiftTab"] = error
            if error == noErr, let reference { hotKeys.append(reference) }
            else { store.message = "\(id == 10 ? "⌥Tab" : "⌥⇧Tab") er allerede i bruk. De andre snarveiene og kortene kan fortsatt brukes." }
        }
        var pinReference: EventHotKeyRef?
        let pinError = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x41444F43, id: 12), GetApplicationEventTarget(), 0, &pinReference)
        registration["pinActiveWindow"] = pinError
        if pinError == noErr, let pinReference { hotKeys.append(pinReference) }
        else { store.message = "⌃⌥A er allerede i bruk. Du kan fortsatt feste vinduer med Legg til eller dra og slipp." }
        var searchReference: EventHotKeyRef?
        let searchError = RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x41444F43, id: 13), GetApplicationEventTarget(), 0, &searchReference)
        registration["searchAllWindows"] = searchError
        if searchError == noErr, let searchReference { hotKeys.append(searchReference) }
        else { store.message = "⌃⌥F er allerede i bruk. Du kan åpne vindussøket fra menyen." }
        UserDefaults.standard.set(registration, forKey: "RuntimeHotKeyState")
        UserDefaults.standard.synchronize()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        switcherTimer?.invalidate()
        for key in hotKeys { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}

if CommandLine.arguments.contains("--status") || CommandLine.arguments.contains("--focus-status") || CommandLine.arguments.contains("--hotkey-status") || CommandLine.arguments.contains("--switcher-status") || CommandLine.arguments.contains("--pin-status") || CommandLine.arguments.contains("--shortcut-status") {
    let key = CommandLine.arguments.contains("--shortcut-status") ? "RuntimeShortcutState" : CommandLine.arguments.contains("--pin-status") ? "RuntimePinState" : CommandLine.arguments.contains("--switcher-status") ? "RuntimeSwitcherState" : CommandLine.arguments.contains("--hotkey-status") ? "RuntimeHotKeyState" : CommandLine.arguments.contains("--focus-status") ? "RuntimeFocusState" : "RuntimeWindowState"
    let state = UserDefaults.standard.persistentDomain(forName: "no.magne.agentdock")?[key] as? [String: Any] ?? [:]
    if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
