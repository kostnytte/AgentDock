import AppKit
import SwiftUI

private let workflowAccent = Color(red: 0.65, green: 0.86, blue: 0.73)
private let workflowBackground = Color(red: 0.075, green: 0.085, blue: 0.095)

struct WindowPinEditor: View {
    @ObservedObject var store: BoardStore
    let window: LiveWindow
    let save: (String, UUID?) -> Void
    let cancel: () -> Void
    @State private var name: String
    @State private var folder: UUID?
    @FocusState private var nameFocused: Bool

    init(store: BoardStore, window: LiveWindow, save: @escaping (String, UUID?) -> Void, cancel: @escaping () -> Void) {
        self.store = store
        self.window = window
        self.save = save
        self.cancel = cancel
        let existing = store.card(for: window)
        _name = State(initialValue: existing?.name ?? (window.title.isEmpty ? window.appName : window.title))
        if let existing { _folder = State(initialValue: store.folderState.folderID(for: existing.id)) }
        else if case .folder(let id) = store.effectiveSwitcherScope { _folder = State(initialValue: id) }
        else { _folder = State(initialValue: nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 11) {
                AppBadge(name: window.appName, bundleID: window.bundleID)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.card(for: window) == nil ? "Fest vindu" : "Oppdater vindu")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(window.appName).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Navn").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField("Hva jobber du med?", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Mappe").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("Mappe", selection: $folder) {
                    Text("Uten mappe").tag(nil as UUID?)
                    ForEach(store.folderState.folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = store.message { Text(message).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Avbryt", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Lagre og åpne") { save(name, folder) }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(25).frame(width: 430).background(workflowBackground).preferredColorScheme(.dark)
            .onAppear { nameFocused = true }
    }
}

struct WindowSearchView: View {
    @ObservedObject var store: BoardStore
    let pin: (LiveWindow) -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finn et arbeidsvindu").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Søk i alle åpne vinduer, også dem du ikke har festet.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Navn, app, vindustittel eller mappe …", text: $store.windowSearchQuery)
                    .textFieldStyle(.plain).focused($searchFocused)
                if !store.windowSearchQuery.isEmpty {
                    Button { store.windowSearchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }.padding(12).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            if !store.permission {
                Text("Åpne settekassen og slå på vindustilgang for å søke i appene dine.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if store.windowSearchEntries.isEmpty && !store.loading {
                            Text("Ingen åpne vinduer funnet.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 35)
                        }
                        ForEach(store.windowSearchEntries) { entry in
                            if let window = store.liveWindows.first(where: { $0.id == entry.id }) {
                                result(entry, window: window).id(entry.id)
                            }
                        }
                    }.padding(2)
                }.onChange(of: store.searchSelectionID) { id in if let id { scroll.scrollTo(id, anchor: .center) } }
            }
            HStack {
                Text("↑↓ velg · Enter åpne · Esc lukk").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Hent på nytt") { store.refresh(discover: true) }.disabled(store.loading)
                Button("Lukk", action: close).keyboardShortcut(.cancelAction)
            }
        }.padding(23).frame(width: 620, height: 560).background(workflowBackground).preferredColorScheme(.dark)
            .onAppear { searchFocused = true }
            .onChange(of: store.windowSearchQuery) { _ in store.searchSelectionID = nil }
    }

    private func result(_ entry: WindowSearchEntry, window: LiveWindow) -> some View {
        let selected = store.selectedSearchWindow?.id == entry.id
        return HStack(spacing: 9) {
            Button { store.searchSelectionID = entry.id; store.openLiveWindow(window) } label: {
                HStack(spacing: 10) {
                    AppBadge(name: window.appName, bundleID: window.bundleID)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text([entry.appName, entry.folder, entry.archived ? "Arkivert" : entry.pinned ? "Festet" : "Ikke festet"]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(selected ? "Valgt" : "")
            if !entry.pinned || entry.archived {
                Button(entry.archived ? "Hent tilbake …" : "Fest …") { pin(window) }.font(.system(size: 11))
            } else {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(workflowAccent).help("Allerede i settekassen")
            }
        }.padding(10)
            .background(selected ? workflowAccent.opacity(0.09) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? workflowAccent.opacity(0.5) : .clear))
    }
}

struct ArchiveView: View {
    @ObservedObject var store: BoardStore
    let close: () -> Void
    @State private var mode = 0
    @State private var unavailableOnly = false
    @State private var query = ""
    @State private var selected: Set<UUID> = []

    private var rows: [WindowCard] {
        let candidates = mode == 0 ? store.unarchivedCards : store.archivedCards
        return candidates.filter { card in
            (mode != 0 || !unavailableOnly || (store.permission && !store.connected(card))) &&
                (query.isEmpty || [card.name, card.appName, card.windowTitle, store.folderName(for: card) ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    private var chosen: Set<UUID> { selected.intersection(Set(rows.map(\.id))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rydd opp og arkiv").font(.system(size: 22, weight: .semibold, design: .rounded))
            Picker("Visning", selection: $mode) {
                Text("Rydd opp · \(store.unarchivedCards.count)").tag(0)
                Text("Arkiv · \(store.archivedCards.count)").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                TextField("Finn kort eller mappe …", text: $query).textFieldStyle(.roundedBorder)
                if mode == 0 { Toggle("Bare utilgjengelige", isOn: $unavailableOnly).toggleStyle(.checkbox).font(.system(size: 11)) }
            }
            HStack {
                Button(chosen.count == rows.count && !rows.isEmpty ? "Fjern valg" : "Velg alle viste") {
                    selected = chosen.count == rows.count ? [] : Set(rows.map(\.id))
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(workflowAccent).disabled(rows.isEmpty)
                Spacer()
                Text("\(chosen.count) valgt").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if store.loading { ProgressView("Oppdaterer vinduer …").font(.system(size: 11)) }
            if unavailableOnly && mode == 0 && !store.permission {
                Text("Vindustilgang må være på for å finne utilgjengelige vinduer.").font(.system(size: 11)).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    if rows.isEmpty { Text(mode == 1 ? "Arkivet er tomt." : "Ingen kort å vise.").foregroundStyle(.secondary).padding(.vertical, 35) }
                    ForEach(rows) { card in
                        Toggle(isOn: Binding(get: { selected.contains(card.id) }, set: { value in
                            if value { selected.insert(card.id) } else { selected.remove(card.id) }
                        })) {
                            HStack(spacing: 10) {
                                CardBadge(store: store, card: card, small: true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text([card.appName, store.folderName(for: card) ?? "", card.paused ? "På pause" : "", store.connected(card) ? "" : "Utilgjengelig"]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 8)
                        }.toggleStyle(.checkbox).padding(.horizontal, 10)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if let error = store.archiveStorageError ?? store.message { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3) }
            HStack {
                if store.archiveUndo != nil {
                    Button("Angre siste arkivendring") { if store.undoArchiveChange() { selected = [] } }.font(.system(size: 11))
                }
                Spacer()
                Button("Lukk", action: close).keyboardShortcut(.cancelAction)
                Button(mode == 0 ? "Arkiver (\(chosen.count))" : "Hent tilbake (\(chosen.count))") {
                    let success = mode == 0 ? store.archiveCards(chosen) : store.restoreArchived(chosen)
                    if success { selected = [] }
                }.disabled(chosen.isEmpty || store.archiveStorageError != nil || store.loading)
            }
            Text("Arkivering skjuler kortet fra settekassen. Arbeidsvinduet fortsetter å være åpent.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(23).frame(width: 620, height: 570).background(workflowBackground).preferredColorScheme(.dark)
            .onChange(of: mode) { _ in selected = [] }
            .onChange(of: unavailableOnly) { _ in selected = [] }
            .onChange(of: query) { _ in selected = [] }
    }
}
