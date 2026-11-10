import SwiftUI
import UniformTypeIdentifiers

private let folderAccent = Color(red: 0.65, green: 0.86, blue: 0.73)
private let folderBackground = Color(red: 0.075, green: 0.085, blue: 0.095)

struct FolderEditorRequest: Identifiable {
    var id = UUID()
    var folder: WindowFolder?
}

struct FolderGroupView<Content: View>: View {
    @ObservedObject var store: BoardStore
    var folder: WindowFolder
    var edit: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var targeted = false

    private var dropHighlighted: Bool { targeted }
    private var activeCards: [WindowCard] { store.active.filter { store.folderState.folderID(for: $0.id) == folder.id } }
    private var pausedCount: Int { store.paused.filter { store.folderState.folderID(for: $0.id) == folder.id }.count }
    private var expanded: Bool {
        folder.expanded || !store.query.isEmpty ||
            (store.switcherSelectionID.map { store.folderState.folderID(for: $0) == folder.id } ?? false)
    }
    private var selected: Bool { store.switcherSelectionID == nil && store.keyboardSelection == .folder(folder.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Button { store.toggleFolder(folder.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).frame(width: 9)
                        Image(systemName: expanded ? "folder.fill" : "folder").font(.system(size: 13)).foregroundStyle(folderAccent)
                        Text(folder.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(dropHighlighted ? "Slipp her" : "\(activeCards.count)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(dropHighlighted ? folderAccent : .secondary)
                        if pausedCount > 0 {
                            Label("\(pausedCount)", systemImage: "pause.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).help("\(activeCards.count) aktive vinduer, \(pausedCount) på pause")
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .overlay(FolderNativeDropSurface(store: store, folder: folder, targeted: $targeted))
                Menu {
                    Button("Rediger mappe og vinduer …", action: edit)
                    Button("Løs opp mappe") { store.dissolveFolder(folder.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 23, height: 24)
                }.menuStyle(.borderlessButton).fixedSize().help("Valg for \(folder.name)")
            }.padding(.horizontal, 9)
                .background(dropHighlighted || selected ? folderAccent.opacity(0.12) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(dropHighlighted || selected ? folderAccent.opacity(0.6) : .clear))
                .help("Slipp et vinduskort på mappenavnet for å flytte det hit")
                .contextMenu {
                    Button("Rediger mappe og vinduer …", action: edit)
                    Button("Løs opp mappe") { store.dissolveFolder(folder.id) }
                }
            if expanded {
                if activeCards.isEmpty {
                    Text(pausedCount > 0 ? "Vinduene i mappen er på pause." : "Dra vinduskort hit, eller rediger mappen for å velge flere.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.bottom, 7)
                        .fixedSize(horizontal: false, vertical: true)
                } else { content().padding(.leading, 8) }
            }
        }
        .contentShape(Rectangle())
        .background(dropHighlighted ? folderAccent.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(dropHighlighted ? folderAccent.opacity(0.8) : .clear, lineWidth: 1.5))

    }
}

struct FolderDestinationMenu: View {
    @ObservedObject var store: BoardStore
    var card: WindowCard
    var body: some View {
        Menu("Flytt til mappe") {
            Button { store.moveCard(card.id, to: nil) } label: {
                if store.folderState.folderID(for: card.id) == nil { Label("Uten mappe", systemImage: "checkmark") }
                else { Text("Uten mappe") }
            }
            if store.folderState.folders.isEmpty { Text("Ingen mapper ennå") }
            ForEach(store.folderState.folders) { folder in
                Button { store.moveCard(card.id, to: folder.id) } label: {
                    if store.folderState.folderID(for: card.id) == folder.id { Label(folder.name, systemImage: "checkmark") }
                    else { Text(folder.name) }
                }
            }
        }
    }
}

struct WindowFolderEditor: View {
    @ObservedObject var store: BoardStore
    var folder: WindowFolder?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var failed = false
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicate: Bool {
        store.folderState.folders.contains { $0.id != folder?.id && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(folder == nil ? "Ny mappe" : "Rediger mappe").font(.system(size: 20, weight: .semibold, design: .rounded))
            TextField("For eksempel Kunder", text: $name).textFieldStyle(.roundedBorder)
            Text("Velg vinduene som skal ligge i mappen.").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if store.cards.isEmpty {
                        Text("Mappen kan opprettes nå og fylles med vinduer senere.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ForEach(store.unarchivedCards) { card in
                        Toggle(isOn: Binding(get: { selected.contains(card.id) }, set: { value in
                            if value { selected.insert(card.id) } else { selected.remove(card.id) }
                        })) {
                            HStack(spacing: 9) {
                                CardBadge(store: store, card: card, small: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(card.name).font(.system(size: 12)).lineLimit(1)
                                    Text([card.appName, store.folderName(for: card) ?? "", card.paused ? "På pause" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 5)
                        }.toggleStyle(.checkbox)
                    }
                }.padding(3)
            }
            if duplicate { Text("Du har allerede en mappe med dette navnet.").font(.system(size: 11)).foregroundStyle(.orange) }
            if failed { Text(store.message ?? "Mappen kunne ikke lagres.").font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Avbryt") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lagre") {
                    if store.saveFolder(id: folder?.id, name: cleanName, cards: selected) { dismiss() }
                    else { failed = true }
                }.keyboardShortcut(.defaultAction).disabled(cleanName.isEmpty || duplicate)
            }
        }.padding(23).frame(width: 420, height: min(550, max(300, CGFloat(store.unarchivedCards.count) * 49 + 205)))
            .background(folderBackground).preferredColorScheme(.dark)
            .onAppear {
                name = folder?.name ?? ""
                if let folder { selected = Set(store.cards.filter { store.folderState.folderID(for: $0.id) == folder.id }.map(\.id)) }
            }
    }
}
