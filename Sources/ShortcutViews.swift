import AppKit
import SwiftUI

struct CardBadge: View {
    @ObservedObject var store: BoardStore
    let card: WindowCard
    var small = false
    var body: some View {
        if store.shortcut(for: card) != nil, let url = store.iconURL(for: card) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                .frame(width: small ? 26 : 36, height: small ? 26 : 36)
        } else { AppBadge(name: card.appName, bundleID: card.bundleID, small: small) }
    }
}

struct ShortcutDestinationMenu: View {
    @ObservedObject var store: BoardStore
    let card: WindowCard
    var body: some View {
        if let target = store.shortcut(for: card) {
            Button("Velg app eller fil på nytt …") { AppDelegate.shared.chooseShortcut(kind: target.kind, editingID: card.id) }
        }
    }
}

struct ShortcutEditor: View {
    @ObservedObject var store: BoardStore
    let target: ShortcutTarget
    let save: (String, UUID?) -> Void
    let cancel: () -> Void
    @State private var name: String
    @State private var folder: UUID?
    @FocusState private var nameFocused: Bool

    init(store: BoardStore, target: ShortcutTarget, existingID: UUID?, save: @escaping (String, UUID?) -> Void, cancel: @escaping () -> Void) {
        self.store = store; self.target = target; self.save = save; self.cancel = cancel
        let existing = store.cards.first { $0.id == existingID }
        _name = State(initialValue: existing?.name ?? ShortcutSupport.defaultName(target))
        if let existing { _folder = State(initialValue: store.folderState.folderID(for: existing.id)) }
        else if case .folder(let id) = store.effectiveSwitcherScope { _folder = State(initialValue: id) }
        else { _folder = State(initialValue: nil) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                if let url = ShortcutSupport.resolvedURL(target) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 38, height: 38)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.kind == .application ? "Fest app" : "Fest fil")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(target.kind == .application ? "Starter appen når du velger snarveien." : "Åpner filen i standardappen når du velger snarveien.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Navn").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField("Navn i AgentDock", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Mappe").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("Mappe", selection: $folder) {
                    Text("Uten mappe").tag(nil as UUID?)
                    ForEach(store.folderState.folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(target.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            if let message = store.message { Text(message).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Avbryt", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Lagre snarvei") { save(name, folder) }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440).background(Color(red: 0.075, green: 0.085, blue: 0.095)).preferredColorScheme(.dark)
            .onAppear { nameFocused = true }
    }
}
