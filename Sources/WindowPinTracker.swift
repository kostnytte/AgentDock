import AppKit
import SwiftUI

// A native window title bar is not a pasteboard drag. Observe only mouse drags
// and window geometry, then pin the actual window identity on release.
final class WindowPinTracker {
    private struct Session {
        let window: LiveWindow
        let originalFrame: CGRect
        var moved = false
    }
    private weak var board: NSWindow?
    private weak var store: BoardStore?
    private var monitor: Any?
    private var timer: Timer?
    private var session: Session?
    private var wasDown = false
    private var hint: NSPanel?
    private var hintGeneration = UUID()
    private let onPin: () -> Void

    init(board: NSWindow, store: BoardStore, onPin: @escaping () -> Void) {
        self.board = board
        self.store = store
        self.onPin = onPin
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown: self.begin(at: NSEvent.mouseLocation)
            case .leftMouseUp: self.finish(at: NSEvent.mouseLocation)
            default: self.update()
            }
        }
        // The Window Server can consume title-bar drag events. Sampling during a
        // drag supplements the event monitor; it never generates input events.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let down = NSEvent.pressedMouseButtons & 1 != 0
            if down && !self.wasDown && self.session == nil { self.begin(at: NSEvent.mouseLocation) }
            if self.session != nil {
                if down { self.update() } else { self.finish(at: NSEvent.mouseLocation) }
            }
            self.wasDown = down
        }
    }

    private func begin(at point: NSPoint) {
        guard session == nil, let board, !board.isMiniaturized,
              let store, store.permission, !(board.isVisible && board.frame.contains(point)),
              let window = WindowAccess.window(at: point), let frame = WindowAccess.frame(window.element) else { return }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let axPoint = CGPoint(x: point.x, y: screenTop - point.y)
        // Only a title-bar gesture qualifies. Dragging selected text or a file
        // across the board must never pin its source window.
        guard frame.contains(axPoint), axPoint.y - frame.minY < 42 else { return }
        session = Session(window: window, originalFrame: frame)
        hintGeneration = UUID()
    }

    private func update() {
        guard var session, board != nil else { return }
        guard let frame = WindowAccess.frame(session.window.element) else { cancel(); return }
        if hypot(frame.minX - session.originalFrame.minX, frame.minY - session.originalFrame.minY) > 9 { session.moved = true }
        self.session = session
        guard session.moved else { return }
        let hovering = dropFrame.contains(NSEvent.mouseLocation)
        showHint(title: hovering ? "Slipp for å feste \(session.window.appName)" : "Dra vinduet hit for å feste",
            detail: "Vinduet legges tilbake. Kortet blir her.", hovering: hovering)
    }

    private func finish(at point: NSPoint) {
        guard var session else { return }
        if let frame = WindowAccess.frame(session.window.element),
           hypot(frame.minX - session.originalFrame.minX, frame.minY - session.originalFrame.minY) > 9 { session.moved = true }
        self.session = nil
        guard board != nil, session.moved, dropFrame.contains(point), let store, store.permission else {
            hint?.orderOut(nil)
            return
        }
        let added = store.pin(session.window)
        WindowAccess.restorePosition(session.window.element, to: session.originalFrame.origin)
        onPin()
        let title = added ? "\(session.window.appName) er festet" : "Vinduet er på bordet"
        store.pinStatus = title
        showHint(title: title, detail: "Gi kortet et eget navn med høyreklikk.", hovering: true)
        let generation = UUID()
        hintGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.hintGeneration == generation else { return }
            self.hint?.orderOut(nil)
            self.store?.pinStatus = nil
        }
    }

    private var dropFrame: NSRect {
        guard let board else { return .zero }
        return board.isVisible ? board.frame : (hint?.frame ?? .zero)
    }

    private func showHint(title: String, detail: String, hovering: Bool) {
        guard let board else { return }
        if hint == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.fullScreenAuxiliary]
            hint = panel
        }
        let width = min(board.frame.width - 20, 380)
        hint?.setFrame(NSRect(x: board.frame.midX - width / 2, y: board.frame.maxY - 100, width: width, height: 76), display: true)
        let view = NSHostingView(rootView: PinHint(title: title, detail: detail, hovering: hovering))
        view.sizingOptions = []
        hint?.contentView = view
        hint?.orderFrontRegardless()
    }

    private func cancel() { session = nil; hint?.orderOut(nil) }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
        hint?.close()
    }
}

private struct PinHint: View {
    let title: String
    let detail: String
    let hovering: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hovering ? "pin.fill" : "arrow.down.right.and.arrow.up.left").font(.system(size: 19))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }.padding(14).foregroundStyle(Color(red: 0.65, green: 0.86, blue: 0.73))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.09, green: 0.13, blue: 0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(hovering ? 0.7 : 0.25), style: StrokeStyle(lineWidth: 1, dash: hovering ? [] : [5, 4])))
    }
}
