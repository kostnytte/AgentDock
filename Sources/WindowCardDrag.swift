import AppKit
import SwiftUI
import UniformTypeIdentifiers

// NSString supplies the standard macOS drag representation. A per-drag token
// binds the payload to this board; arbitrary text and cancelled old drags cannot
// move a card. Drop destinations read the actual payload rather than a stale ID.
let windowCardDragType = UTType.plainText
func windowCardDragProvider(_ id: UUID, store: BoardStore) -> NSItemProvider {
    NSItemProvider(object: store.beginCardDrag(id) as NSString)
}

struct WindowCardDragHandle: NSViewRepresentable {
    var store: BoardStore
    var card: WindowCard
    func makeNSView(context: Context) -> NativeCardDragHandle { NativeCardDragHandle(store: store, card: card) }
    func updateNSView(_ view: NativeCardDragHandle, context: Context) { view.store = store; view.card = card }
}

final class NativeCardDragHandle: NSView, NSDraggingSource {
    var store: BoardStore
    var card: WindowCard
    private var mouseDownPoint: NSPoint?
    init(store: BoardStore, card: WindowCard) {
        self.store = store
        self.card = card
        super.init(frame: .zero)
        toolTip = "Dra kortet til en mappe"
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Dra \(card.name) til en mappe")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for offset in [-3.0, 0.0, 3.0] {
            path.move(to: NSPoint(x: bounds.midX - 4.5, y: bounds.midY + offset))
            path.line(to: NSPoint(x: bounds.midX + 4.5, y: bounds.midY + offset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
        mouseDownPoint = nil
        let payload = store.beginCardDrag(card.id)
        let item = NSDraggingItem(pasteboardWriter: payload as NSString)
        let image = NSImage(size: NSSize(width: 190, height: 32), flipped: false) { rect in
            NSColor(calibratedWhite: 0.16, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            (self.card.name as NSString).draw(in: rect.insetBy(dx: 10, dy: 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            return true
        }
        item.setDraggingFrame(NSRect(x: bounds.minX, y: bounds.midY - 16, width: 190, height: 32), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty { store.cancelCardDrag() }
    }
}

@discardableResult
func receiveWindowCardDrop(_ providers: [NSItemProvider], store: BoardStore, folder: UUID?, before: UUID? = nil) -> Bool {
    guard store.draggingID != nil, let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
    provider.loadObject(ofClass: NSString.self) { value, error in
        guard error == nil, let payload = value as? String else { return }
        DispatchQueue.main.async { _ = store.completeCardDrop(payload, to: folder, before: before) }
    }
    return true
}

struct FolderNativeDropSurface: NSViewRepresentable {
    var store: BoardStore
    var folder: WindowFolder
    @Binding var targeted: Bool
    func makeNSView(context: Context) -> NativeFolderDropButton {
        NativeFolderDropButton(store: store, folder: folder, targetChanged: { targeted = $0 })
    }
    func updateNSView(_ view: NativeFolderDropButton, context: Context) {
        view.store = store
        view.folder = folder
        view.targetChanged = { targeted = $0 }
        view.setAccessibilityLabel(folder.name)
    }
}

// A real native destination reads the pasteboard synchronously, before the
// drag ends. The transparent button also preserves clicking to expand/collapse.
final class NativeFolderDropButton: NSButton {
    var store: BoardStore
    var folder: WindowFolder
    var targetChanged: (Bool) -> Void
    init(store: BoardStore, folder: WindowFolder, targetChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.folder = folder
        self.targetChanged = targetChanged
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(toggleFolder)
        registerForDraggedTypes([.string])
        toolTip = "Slipp et vinduskort på mappenavnet for å flytte det hit"
        setAccessibilityLabel(folder.name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override func draw(_ dirtyRect: NSRect) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func toggleFolder() { store.toggleFolder(folder.id) }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = sender.draggingPasteboard.string(forType: .string) else { return false }
        return store.acceptsCardDrag(payload) && store.folderState.folders.contains { $0.id == folder.id }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(sender)
        targetChanged(accepted)
        return accepted ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .move : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { targetChanged(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targetChanged(false)
        guard accepts(sender), let payload = sender.draggingPasteboard.string(forType: .string) else { return false }
        return store.completeCardDrop(payload, to: folder.id)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { targetChanged(false) }
}

struct CardDrop: DropDelegate {
    var store: BoardStore
    var target: UUID
    func validateDrop(info: DropInfo) -> Bool {
        guard let source = store.draggingID, source != target,
              let from = store.cards.first(where: { $0.id == source }),
              let to = store.cards.first(where: { $0.id == target }), from.paused == to.paused else { return false }
        return store.folderState.folderID(for: source) == store.folderState.folderID(for: target) ||
            store.folderState.folderID(for: target) != nil
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let source = store.draggingID else { return false }
        let folder = store.folderState.folderID(for: target)
        // Child rows receive drops before their enclosing SwiftUI folder. An
        // incoming card must file into that folder rather than be swallowed by
        // a reorder handler that only supports cards already in the same group.
        let sameFolder = store.folderState.folderID(for: source) == folder
        return receiveWindowCardDrop(info.itemProviders(for: [windowCardDragType]), store: store,
            folder: folder, before: sameFolder ? target : nil)
    }
}

