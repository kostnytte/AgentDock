import AppKit

// Local file/application targets are deliberately separate from AX windows.
// Opening a shortcut never guesses which old agent conversation to recreate.
enum ShortcutSupport {
    enum Failure: LocalizedError {
        case missing, notApplication, directory, ownApplication
        var errorDescription: String? {
            switch self {
            case .missing: return "Filen eller appen er ikke tilgjengelig. Velg den på nytt."
            case .notApplication: return "Velg en gyldig Mac-app (.app)."
            case .directory: return "Velg en fil, ikke en mappe."
            case .ownApplication: return "AgentDock trenger ikke en snarvei til seg selv."
            }
        }
    }
    static func makeTarget(url: URL, kind requested: ShortcutKind) throws -> ShortcutTarget {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw Failure.missing }
        let kind: ShortcutKind = url.pathExtension.lowercased() == "app" ? .application : requested
        var bundleID: String?
        if kind == .application {
            guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
                  bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String != nil else { throw Failure.notApplication }
            bundleID = bundle.bundleIdentifier
            guard bundleID != "no.magne.agentdock", !(bundleID?.hasPrefix("no.magne.agentdock.") ?? false) else { throw Failure.ownApplication }
        } else if directory.boolValue { throw Failure.directory }
        let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return ShortcutTarget(kind: kind, path: url.path, bookmark: bookmark, applicationBundleID: bundleID)
    }
    static func resolvedURL(_ target: ShortcutTarget) -> URL? {
        if let bookmark = target.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale), url.isFileURL,
               FileManager.default.fileExists(atPath: url.path) { return url.standardizedFileURL }
        }
        let path = URL(fileURLWithPath: target.path).standardizedFileURL
        if FileManager.default.fileExists(atPath: path.path) { return path }
        if target.kind == .application, let id = target.applicationBundleID,
           let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           FileManager.default.fileExists(atPath: installed.path) { return installed }
        return nil
    }
    static func sameTarget(_ left: ShortcutTarget, _ right: ShortcutTarget) -> Bool {
        guard left.kind == right.kind else { return false }
        let lhs = (resolvedURL(left) ?? URL(fileURLWithPath: left.path)).resolvingSymlinksInPath().standardizedFileURL
        let rhs = (resolvedURL(right) ?? URL(fileURLWithPath: right.path)).resolvingSymlinksInPath().standardizedFileURL
        return lhs == rhs
    }
    static func defaultName(_ target: ShortcutTarget) -> String {
        let url = resolvedURL(target) ?? URL(fileURLWithPath: target.path)
        return target.kind == .application ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }
    static func open(_ target: ShortcutTarget, url: URL, completion: @escaping (Bool, String?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        let finished: (NSRunningApplication?, Error?) -> Void = { app, error in
            completion(app != nil && error == nil, error?.localizedDescription)
        }
        if target.kind == .application {
            let id = Bundle(url: url)?.bundleIdentifier
            guard id != "no.magne.agentdock", !(id?.hasPrefix("no.magne.agentdock.") ?? false) else {
                completion(false, Failure.ownApplication.localizedDescription); return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: finished)
        } else {
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
                completion(false, "Ingen standardapp er valgt for denne filtypen. Velg en app for filen i Finder."); return
            }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration, completionHandler: finished)
        }
    }
}
