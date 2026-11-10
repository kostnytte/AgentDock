import AppKit
import SwiftUI
import ApplicationServices

// Capture the focused AX window before opening any AgentDock UI. This works
// for an app that has never been scanned or added to the board, too.
enum WindowPinShortcut {
    static func capture() -> LiveWindow? {
        guard WindowAccess.trusted, let element = WindowAccess.focusedWindow() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid(),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.activationPolicy == .regular else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard WindowAccess.attribute(element, kAXRoleAttribute) as? String == kAXWindowRole,
              WindowAccess.attribute(element, kAXSubroleAttribute) as? String != kAXDialogSubrole else { return nil }
        return LiveWindow(id: UUID(), element: element, pid: pid,
            bundleID: app.bundleIdentifier ?? "pid:\(pid)", appName: app.localizedName ?? "App",
            title: WindowAccess.attribute(element, kAXTitleAttribute) as? String ?? "")
    }
}

// Feedback must never activate AgentDock, move the source window, or take
// keyboard focus away from the user's work.
final class QuickPinFeedback {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func show(title: String, detail: String, success: Bool) {
        dismissal?.cancel()
        let panel = self.panel ?? NSPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(360, frame.width - 40)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - 104, width: width, height: 80), display: false)
        panel.contentView = NSHostingView(rootView: QuickPinMessage(title: title, detail: detail, success: success))
        panel.orderFrontRegardless()
        let task = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        dismissal = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3, execute: task)
    }
}

private struct QuickPinMessage: View {
    let title: String
    let detail: String
    let success: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: success ? "checkmark.circle.fill" : "info.circle")
                .font(.system(size: 24)).foregroundStyle(success ? Color(red: 0.65, green: 0.86, blue: 0.73) : .orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white).background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.15)))
            .preferredColorScheme(.dark)
    }
}

extension AppDelegate {
    func pinActiveWindow() {
        guard !store.preview else { return }
        // No showBoard()/activate() before this capture.
        guard WindowAccess.trusted else {
            quickPinFeedback.show(title: "Vindustilgang mangler", detail: "Åpne AgentDock og velg Innstillinger.", success: false)
            recordQuickPin("accessMissing")
            return
        }
        guard let window = WindowPinShortcut.capture() else {
            quickPinFeedback.show(title: "Velg et arbeidsvindu først", detail: "Klikk i vinduet du vil legge til, og trykk ⌃⌥A.", success: false)
            recordQuickPin("noWindow")
            return
        }
        showPinEditor(for: window)
        recordQuickPin("editorShown")
    }

    private func recordQuickPin(_ result: String) {
        UserDefaults.standard.set(["result": result, "time": Date().timeIntervalSince1970,
            "cards": store.cards.count, "pid": Int(getpid())] as [String: Any], forKey: "RuntimePinState")
        UserDefaults.standard.synchronize()
    }
}
