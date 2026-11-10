import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let boardBackground = Color(red: 0.075, green: 0.085, blue: 0.095)
private let surface = Color(red: 0.115, green: 0.125, blue: 0.14)
private let mint = Color(red: 0.65, green: 0.86, blue: 0.73)

func appColor(_ name: String) -> Color {
    let name = name.lowercased()
    if name.contains("claude") { return Color(red: 0.88, green: 0.58, blue: 0.43) }
    if name.contains("codex") { return Color(red: 0.80, green: 0.80, blue: 0.94) }
    if name.contains("praksis") { return mint }
    if name.contains("chrome") || name.contains("safari") { return Color(red: 0.53, green: 0.73, blue: 0.94) }
    return Color(red: 0.82, green: 0.74, blue: 0.57)
}

struct AppBadge: View {
    var name: String
    var bundleID: String
    var small = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: small ? 6 : 9).fill(appColor(name).opacity(0.12))
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(small ? 3 : 5)
            } else {
                Text(String(name.prefix(1))).font(.system(size: small ? 12 : 17, weight: .semibold, design: .rounded)).foregroundStyle(appColor(name))
            }
        }.frame(width: small ? 26 : 36, height: small ? 26 : 36)
    }
}

struct BoardView: View {
    @ObservedObject var store: BoardStore
    @State private var showingPicker = false
    @State private var editing: WindowCard?
    @State private var folderEditor: FolderEditorRequest?
    @FocusState private var searchFocused: Bool
    private let columns = [GridItem(.adaptive(minimum: 208), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if store.compact { compactHeader } else { header }
            ScrollViewReader { scroll in
              ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = store.storageError {
                        notice("Lagring trenger oppmerksomhet", detail: error, icon: "externaldrive.badge.exclamationmark")
                    }
                    if !store.permission { permissionCard }
                    if let error = store.shortcutStorageError { notice("Snarveier trenger oppmerksomhet", detail: error, icon: "link") }
                    if let error = store.archiveStorageError { notice("Arkivet trenger oppmerksomhet", detail: error, icon: "archivebox") }
                    if let error = store.folderStorageError { notice("Mapper trenger oppmerksomhet", detail: error, icon: "folder.badge.questionmark") }
                    if let message = store.message {
                        HStack(alignment: .top, spacing: 8) {
                            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { store.message = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).help("Lukk beskjed")
                        }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if store.cards.isEmpty && store.folderState.folders.isEmpty { emptyBoard }
                    else {
                        activeSection
                        if !store.paused.isEmpty { pausedSection }
                        if store.active.isEmpty && store.paused.isEmpty && !store.query.isEmpty {
                            notice("Ingen treff", detail: "Søk etter et navn, en app eller et prosjekt.", icon: "magnifyingglass")
                        }
                    }
                }.padding(store.compact ? 14 : 22)
              }.onChange(of: store.switcherSelectionID) { id in
                  if let id { DispatchQueue.main.async { scroll.scrollTo(BoardNavigationItem.window(id), anchor: .center) } }
              }.onChange(of: store.keyboardSelection) { item in
                  if let item { DispatchQueue.main.async { scroll.scrollTo(item, anchor: .center) } }
              }
            }
            footer
        }
        .background(boardBackground)
        .foregroundStyle(Color.white.opacity(0.92))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPicker) { WindowPicker(store: store) }
        .sheet(item: $editing) { card in EditCardView(card: card) { name, project in store.edit(card.id, name: name, project: project) } }
        .sheet(item: $folderEditor) { request in WindowFolderEditor(store: store, folder: request.folder) }
    }

    private var compactHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(mint).font(.system(size: 12))
                Text("AgentDock").font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button { folderEditor = FolderEditorRequest(folder: nil) } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 12)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).foregroundStyle(mint).help("Ny mappe").accessibilityLabel("Ny mappe")
                addMenu
                optionsMenu
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("Finn et vindu …", text: $store.query).textFieldStyle(.plain).font(.system(size: 11)).focused($searchFocused)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).hidden().accessibilityHidden(true)
        }.padding(.horizontal, 14).padding(.top, 12)
    }

    private var addMenu: some View {
        Menu {
            Button("Åpent vindu …") { showingPicker = true }.disabled(!store.permission).keyboardShortcut("n", modifiers: .command)
            Button("App …") { AppDelegate.shared.chooseApplicationShortcut() }
            Button("Fil …") { AppDelegate.shared.chooseFileShortcut() }
        } label: {
            if store.compact {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24)
            } else {
                Label("Legg til", systemImage: "plus").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                    .background(mint, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(boardBackground)
            }
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(mint)
            .help("Legg til et åpent vindu, en app eller en fil").accessibilityLabel("Legg til")
    }

    private var optionsMenu: some View {
        Menu {
            Button("Søk i alle åpne vinduer …") { AppDelegate.shared.showWindowSearchAction() }
            Button("Rydd opp og arkiv …") { AppDelegate.shared.showArchive() }
            Divider()
            Button("Ny mappe …") { folderEditor = FolderEditorRequest(folder: nil) }
            Toggle("Kompakt oversikt", isOn: Binding(get: { store.compact }, set: { store.compact = $0; store.compactChanged?($0) }))
            Button("Hent vinduer på nytt") { store.refresh(discover: true) }
            Divider()
            Text("Skjules når du bytter til et annet vindu")
            Text("Dra en tittellinje hit for å feste vinduet")
            Text("⌃⌥Mellomrom viser eller skjuler oversikten")
            Text("⌃⌥1–9 åpner aktive kort")
            Text("⌃⌥A velger navn og mappe for aktivt vindu")
            Text("⌃⌥F søker i alle åpne vinduer")
            Text("⌥Tab blar mellom vinduer, slipp ⌥ for å velge")
            Text("⌥⇧Tab blar bakover")
            Text("↑↓ velger, →← åpner/lukker mapper, Enter åpner vinduet")
            Divider()
            Button("Avslutt AgentDock") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).frame(width: 24, height: 24)
        }.menuStyle(.borderlessButton).fixedSize().help("Valg og hurtigtaster")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(mint)
                    Text("AGENTDOCK").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2.2)
                }
                Spacer()
                optionsMenu
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Din settekasse.").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-0.8)
                    Text("Det du jobber med. Ett sted.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                addMenu
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.white.opacity(0.38))
                TextField("Finn et vindu eller prosjekt …", text: $store.query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(11).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.065)))
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).hidden().accessibilityHidden(true)
        }.padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 0)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(mint).frame(width: 5, height: 5)
                Text("PÅ BORDET").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Text("\(store.active.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                Spacer()
                if !store.compact { Text("Dra for å sortere").font(.system(size: 10)).foregroundStyle(.white.opacity(0.28)) }
            }.foregroundStyle(.white.opacity(0.65))
            if store.active.isEmpty && store.query.isEmpty && store.folderState.folders.isEmpty {
                Text("Litt mer luft. Hent tilbake et kort fra pause når du trenger det.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            cardList(store.unfiledActive)
            ForEach(store.visibleFolders) { folder in
                FolderGroupView(store: store, folder: folder, edit: { folderEditor = FolderEditorRequest(folder: folder) }) {
                    cardList(store.active.filter { store.folderState.folderID(for: $0.id) == folder.id })
                }.id(BoardNavigationItem.folder(folder.id))
            }
            if store.compact {
                Text(store.pinStatus ?? "⌃⌥A fest vindu · ⌃⌥F søk i alle vinduer")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3)).padding(.top, 3)
            }
        }
    }

    @ViewBuilder private func cardList(_ cards: [WindowCard]) -> some View {
            if store.compact {
                LazyVStack(spacing: 6) {
                    ForEach(cards) { card in
                        CompactCardView(store: store, card: card, edit: { editing = card })
                            .id(BoardNavigationItem.window(card.id))
                            .onDrop(of: [windowCardDragType], delegate: CardDrop(store: store, target: card.id))
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        WindowCardView(store: store, card: card, edit: { editing = card })
                            .id(BoardNavigationItem.window(card.id))
                            .onDrop(of: [windowCardDragType], delegate: CardDrop(store: store, target: card.id))
                    }
                }
            }
    }

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { store.pausedExpanded.toggle(); store.keyboardSelection = .pausedSection } } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pause.circle").font(.system(size: 12))
                    Text("PÅ PAUSE").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                    Text("\(store.paused.count)").font(.system(size: 10, design: .monospaced))
                    Spacer()
                    Image(systemName: store.pausedExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                }.foregroundStyle(store.switcherSelectionID == nil && store.keyboardSelection == .pausedSection ? mint : .white.opacity(0.40))
            }.buttonStyle(.plain).accessibilityValue(store.keyboardSelection == .pausedSection ? "Valgt" : "")
            if store.pausedExpanded {
                VStack(spacing: 1) {
                    ForEach(store.paused) { card in
                        HStack(spacing: 9) {
                            Button { store.focus(card) } label: {
                                HStack(spacing: 9) {
                                    CardBadge(store: store, card: card, small: true).opacity(0.6)
                                    Text(card.name).font(.system(size: 11)).lineLimit(1).foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                }.padding(.vertical, 7)
                            }.buttonStyle(.plain).help("Hent frem vinduet")
                                .accessibilityValue(store.keyboardSelection == .window(card.id) ? "Valgt" : "")
                            Button { withAnimation { store.togglePause(card.id) } } label: {
                                Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(mint).frame(width: 26, height: 26)
                            }.buttonStyle(.plain).help("Tilbake på bordet").accessibilityLabel("Fortsett \(card.name)")
                        }.padding(.horizontal, 10)
                            .background(store.keyboardSelection == .window(card.id) ? mint.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .id(BoardNavigationItem.window(card.id)).contextMenu { cardMenu(card) }
                    }
                }.background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                if !store.compact {
                    Text("Bare oversikten er på pause. Arbeidet i appene fortsetter.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.28))
                }
            }
        }.padding(.top, 5).id(BoardNavigationItem.pausedSection)
    }

    @ViewBuilder private func cardMenu(_ card: WindowCard) -> some View {
        Button("Endre navn og prosjekt …") { editing = card }
        FolderDestinationMenu(store: store, card: card)
        Button("Tilbake på bordet") { store.togglePause(card.id) }
        Divider()
        Button("Ta ut av oversikten") { store.remove(card.id) }
    }

    private var permissionCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "rectangle.on.rectangle").font(.system(size: 15)).foregroundStyle(mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vindustilgang mangler").font(.system(size: 11, weight: .medium))
                Text("Kortene dine er bevart.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Innstillinger") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }.buttonStyle(.plain).foregroundStyle(mint).font(.system(size: 10, weight: .medium))
                .help("Åpne Tilgjengelighet i Systeminnstillinger")
        }.padding(11).background(mint.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("En plass til hvert arbeidsvindu.").font(.system(size: 15, weight: .medium))
            VStack(alignment: .leading, spacing: 13) {
                emptyStep("1", "Velg vinduene du jobber med", "Claude, fem Codex-vinduer, Praksis, Chrome …")
                emptyStep("2", "Gi dem navn som betyr noe", "For eksempel «API», «Testmiljø» eller «Sparring».")
                emptyStep("3", "Sett resten på pause", "Mindre oppmerksomhet i oversikten, uten å stoppe noe.")
            }
            if store.permission {
                Button("Finn åpne vinduer") { showingPicker = true }.buttonStyle(.bordered).tint(mint)
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(mint)
                .frame(width: 25, height: 25).background(mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func notice(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.switcherSelectionID != nil {
                Text("Slipp ⌥ for å velge").font(.system(size: 10, weight: .medium)).foregroundStyle(mint)
            } else if store.folderUndo != nil {
                Text("Mappen er løst opp.").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Angre") { store.undoDissolveFolder() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(mint)
            } else if store.removedCard != nil {
                Text("Kortet er tatt ut.").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Angre") { store.undoRemove() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(mint)
            } else {
                Text(store.compact ? "⌃⌥Mellomrom" : "⌃⌥Mellomrom: vis/skjul").font(.system(size: 9))
            }
            Spacer()
            Text("⌃⌥1–9: bytt vindu").font(.system(size: 9))
        }.foregroundStyle(.white.opacity(0.32)).padding(.horizontal, 22).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.055)).frame(height: 1) }
    }
}

struct CompactCardView: View {
    @ObservedObject var store: BoardStore
    var card: WindowCard
    var edit: () -> Void
    var body: some View {
        let focused = store.focusedID == card.id
        let highlighted = store.switcherSelectionID.map { $0 == card.id } ?? store.keyboardSelection.map { $0 == .window(card.id) } ?? focused
        HStack(spacing: 7) {
            WindowCardDragHandle(store: store, card: card).frame(width: 14, height: 28)
            Button { store.focus(card) } label: {
                HStack(spacing: 9) {
                    CardBadge(store: store, card: card, small: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(store.subtitle(for: card))
                            .font(.system(size: 9)).foregroundStyle(focused ? mint : .white.opacity(0.37)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if focused { Circle().fill(mint).frame(width: 4, height: 4) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(card.windowTitle)
                .accessibilityValue(highlighted ? "Valgt" : "")
            Button { store.togglePause(card.id) } label: {
                Image(systemName: "pause").font(.system(size: 9)).frame(width: 21, height: 25).foregroundStyle(.white.opacity(0.35))
            }.buttonStyle(.plain).help("Pause i oversikten").accessibilityLabel("Sett \(card.name) på pause")
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(highlighted ? mint.opacity(0.07) : surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(highlighted ? mint.opacity(0.55) : .white.opacity(0.04)))
            .contextMenu {
                Button(store.shortcut(for: card) == nil ? "Hent frem vinduet" : "Åpne snarveien") { store.focus(card) }
                ShortcutDestinationMenu(store: store, card: card)
                Button("Endre navn og prosjekt …", action: edit)
                FolderDestinationMenu(store: store, card: card)
                Button("Sett på pause i oversikten") { store.togglePause(card.id) }
                Divider()
                Button("Ta ut av oversikten") { store.remove(card.id) }
            }
    }
}

struct WindowCardView: View {
    @ObservedObject var store: BoardStore
    var card: WindowCard
    var edit: () -> Void
    @State private var hovering = false

    var body: some View {
        let focused = store.focusedID == card.id
        let highlighted = store.switcherSelectionID.map { $0 == card.id } ?? store.keyboardSelection.map { $0 == .window(card.id) } ?? focused
        let online = store.connected(card)
        let number = store.cards.filter { !$0.paused }.firstIndex(where: { $0.id == card.id }).map { $0 + 1 } ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CardBadge(store: store, card: card)
                WindowCardDragHandle(store: store, card: card).frame(width: 20, height: 28)
                Spacer()
                Button { store.togglePause(card.id) } label: {
                    Image(systemName: "pause").font(.system(size: 11, weight: .semibold)).frame(width: 25, height: 25)
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.45)).opacity(hovering ? 1 : 0.25)
                    .help("Sett kortet på pause. Agenten fortsetter.").accessibilityLabel("Sett \(card.name) på pause")
            }.padding(.bottom, 13)
            Button { store.focus(card) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(card.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).frame(height: 36, alignment: .topLeading)
                    HStack(spacing: 5) {
                        Text(card.appName).foregroundStyle(appColor(card.appName))
                        if !card.project.isEmpty { Text("·").foregroundStyle(.secondary); Text(card.project).foregroundStyle(.white.opacity(0.45)) }
                    }.font(.system(size: 10)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(focused ? mint : Color.white.opacity(online ? 0.22 : 0.10)).frame(width: 4, height: 4)
                        Text(store.shortcut(for: card) != nil ? (online ? "Åpnes ved valg" : "Målet er ikke tilgjengelig") : (focused ? "I fokus" : online ? "Klar" : "Vindu ikke tilgjengelig"))
                            .foregroundStyle(focused ? mint : .white.opacity(0.32))
                        Spacer()
                        if number > 0 && number <= 9 { Text("⌃⌥\(number)").foregroundStyle(.white.opacity(0.24)) }
                    }.font(.system(size: 9)).padding(.top, 7)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(card.windowTitle.isEmpty ? card.appName : card.windowTitle)
                .accessibilityValue(highlighted ? "Valgt" : "")
        }
        .padding(15).background(highlighted ? mint.opacity(0.055) : surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(highlighted ? mint.opacity(0.5) : .white.opacity(hovering ? 0.16 : 0.055), lineWidth: 1))
        .onHover { hovering = $0 }
        .contextMenu {
            Button(store.shortcut(for: card) == nil ? "Hent frem vinduet" : "Åpne snarveien") { store.focus(card) }
                ShortcutDestinationMenu(store: store, card: card)
            Button("Endre navn og prosjekt …", action: edit)
            FolderDestinationMenu(store: store, card: card)
            Button("Sett på pause i oversikten") { store.togglePause(card.id) }
            Divider()
            Button("Ta ut av oversikten") { store.remove(card.id) }
        }
    }
}

struct WindowPicker: View {
    @ObservedObject var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var groups: [(String, [LiveWindow])] {
        let filtered = store.liveWindows.filter { search.isEmpty || ($0.appName + " " + $0.title).localizedCaseInsensitiveContains(search) }
        return Dictionary(grouping: filtered, by: \.appName).sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Velg plassene på bordet").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Legg til vinduene du vil ha oversikt over.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
            }
            TextField("Søk etter app eller vindu …", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !store.loading && groups.isEmpty {
                        Text("Ingen tilgjengelige vinduer. Sjekk Tilgjengelighet, og prøv «Hent på nytt».")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(groups, id: \.0) { appName, windows in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(appName).font(.system(size: 11, weight: .semibold)).foregroundStyle(appColor(appName))
                                Spacer()
                                Button("Legg til alle") { for window in windows { store.add(window) } }.font(.system(size: 10)).buttonStyle(.plain)
                            }
                            ForEach(windows) { window in
                                Button {
                                    dismiss()
                                    DispatchQueue.main.async { AppDelegate.shared.showPinEditor(for: window) }
                                } label: {
                                    HStack(spacing: 10) {
                                        AppBadge(name: window.appName, bundleID: window.bundleID, small: true)
                                        Text(window.title.isEmpty ? "Vindu uten tittel" : window.title).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: store.contains(window) ? "checkmark.circle.fill" : "plus.circle")
                                            .foregroundStyle(store.contains(window) ? mint : .white.opacity(0.4))
                                    }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).disabled(store.contains(window))
                            }
                        }
                    }
                }
            }
            Text("Chrome og andre nettlesere vises per vindu i denne versjonen.").font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Button("Hent på nytt") { store.refresh(discover: true) }.disabled(store.loading)
                Spacer()
                Button("Ferdig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 510, height: 550).background(boardBackground).preferredColorScheme(.dark)
            .onAppear { store.discovering = true; store.refresh(discover: true) }
            .onDisappear { store.discovering = false }
    }
}

struct EditCardView: View {
    var card: WindowCard
    var save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var project = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Gi vinduet en plass").font(.system(size: 20, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Text("Navn i settekassen").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("For eksempel API og integrasjoner", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Prosjekt · valgfritt").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("For eksempel Praksis", text: $project).textFieldStyle(.roundedBorder)
            }
            Text("Navnet endres bare i AgentDock.").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Avbryt") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lagre") { save(name, project); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(25).frame(width: 390).background(boardBackground).preferredColorScheme(.dark)
            .onAppear { name = card.name; project = card.project }
    }
}
