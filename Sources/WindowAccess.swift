import AppKit
import ApplicationServices

struct LiveWindow: Identifiable {
    let id: UUID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
}

enum WindowAccess {
    private static var focusRequest = UUID()
    static var trusted: Bool { AXIsProcessTrusted() }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    static func windows(applications: [NSRunningApplication], previous: [LiveWindow]) -> [LiveWindow] {
        guard trusted else { return [] }
        var result: [LiveWindow] = []
        for app in applications where app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.18)
            guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                let role = attribute(window, kAXRoleAttribute) as? String
                let subrole = attribute(window, kAXSubroleAttribute) as? String
                guard role == kAXWindowRole, subrole != kAXDialogSubrole,
                      (attribute(window, kAXParentAttribute) != nil) else { continue }
                let title = attribute(window, kAXTitleAttribute) as? String ?? ""
                let old = previous.first { $0.pid == app.processIdentifier && CFEqual($0.element, window) }
                result.append(LiveWindow(id: old?.id ?? UUID(), element: window, pid: app.processIdentifier,
                    bundleID: app.bundleIdentifier ?? "pid:\(app.processIdentifier)", appName: app.localizedName ?? "App", title: title))
            }
        }
        return result
    }

    static func focusedWindow() -> AXUIElement? {
        guard trusted, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let value = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func window(at screenPoint: NSPoint) -> LiveWindow? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(screenPoint.x), Float(top - screenPoint.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<12 {
            if (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole { break }
            if let value = attribute(element, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                element = value as! AXUIElement
                break
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        guard (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid(),
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.15)
        return LiveWindow(id: UUID(), element: element, pid: pid, bundleID: app.bundleIdentifier ?? "pid:\(pid)",
            appName: app.localizedName ?? "App", title: attribute(element, kAXTitleAttribute) as? String ?? "")
    }

    static func restorePosition(_ element: AXUIElement, to point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    static func focus(_ window: LiveWindow, completion: @escaping (Bool) -> Void) {
        let request = UUID()
        focusRequest = request
        // The caller closes the popover first. Let AppKit finish dismissing it
        // before transferring keyboard focus to the selected application's window.
        DispatchQueue.main.async {
            guard request == focusRequest else { return }
            guard trusted, let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
                recordFocus(["success": false, "access": trusted, "stage": "prepare"])
                completion(false)
                return
            }
            let root = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(root, 0.25)
            AXUIElementSetMessagingTimeout(window.element, 0.25)
            var diagnostics: [String: Any] = ["access": true, "pid": Int(window.pid)]
            if (attribute(window.element, kAXMinimizedAttribute) as? Bool) == true {
                diagnostics["unminimize"] = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse).rawValue
            }
            // activate() is a request, not a synchronous verdict about whether
            // this particular window can be focused. Never abort on its Bool.
            diagnostics["activationAccepted"] = app.activate(options: [.activateIgnoringOtherApps])

            func raiseSelectedWindow() {
                diagnostics["frontmost"] = AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue).rawValue
                diagnostics["main"] = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue).rawValue
                diagnostics["raise"] = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString).rawValue
                diagnostics["focusWindow"] = AXUIElementSetAttributeValue(root, kAXFocusedWindowAttribute as CFString, window.element).rawValue
            }
            func verify() -> Bool {
                let front = (attribute(root, kAXFrontmostAttribute) as? Bool) == true ||
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
                guard front, let focused = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
                return CFEqual(focused, window.element)
            }
            raiseSelectedWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard request == focusRequest else { return }
                if verify() {
                    diagnostics["success"] = true
                    recordFocus(diagnostics)
                    completion(true)
                    return
                }
                // Some apps update their window focus on the next run-loop turn.
                raiseSelectedWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard request == focusRequest else { return }
                    let success = verify()
                    diagnostics["success"] = success
                    recordFocus(diagnostics)
                    completion(success)
                }
            }
        }
    }

    private static func recordFocus(_ values: [String: Any]) {
        var values = values
        values["time"] = Date().timeIntervalSince1970
        UserDefaults.standard.set(values, forKey: "RuntimeFocusState")
        UserDefaults.standard.synchronize()
    }
}
