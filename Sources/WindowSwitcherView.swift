import AppKit
import SwiftUI

// A separate surface for the global gesture. The menubar board is unchanged.
final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct WindowSwitcherView: View {
    @ObservedObject var store: BoardStore
    let choose: (UUID) -> Void
    private let accent = Color(red: 0.65, green: 0.86, blue: 0.73)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(accent)
                Text("AgentDock").fontWeight(.semibold)
                Spacer()
                Text("\(store.switcherCards.count) valg").foregroundStyle(.secondary)
            }
            .font(.system(size: 12)).padding(.horizontal, 25).padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.switcherScopes, id: \.self) { scope in
                        Button { store.setSwitcherScope(scope) } label: {
                            Text("\(store.scopeName(scope)) · \(store.scopeCount(scope))")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(store.effectiveSwitcherScope == scope ? accent.opacity(0.18) : .white.opacity(0.04), in: Capsule())
                                .overlay(Capsule().strokeBorder(store.effectiveSwitcherScope == scope ? accent.opacity(0.6) : .clear))
                        }.buttonStyle(.plain).accessibilityValue(store.effectiveSwitcherScope == scope ? "Valgt mappe" : "")
                    }
                }.padding(.horizontal, 22).padding(.top, 13)
            }.frame(height: 42)

            if store.switcherCards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Ingen tilgjengelige vinduer i \(store.scopeName(store.effectiveSwitcherScope))").font(.headline)
                    Text(store.permission ? "Velg en annen mappe, eller fest flere vinduer." : "Slå på vindustilgang i AgentDock.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(store.switcherCards) { card in
                                tile(card).id(card.id)
                            }
                        }.padding(.horizontal, 22).padding(.vertical, 18)
                    }
                    .onAppear { if let id = store.switcherSelectionID { scroll.scrollTo(id, anchor: .center) } }
                    .onChange(of: store.switcherSelectionID) { id in
                        if let id, !store.switcherSelectionFromPointer { scroll.scrollTo(id, anchor: .center) }
                    }
                }
            }

            Divider().opacity(0.4)
            if let message = store.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.orange)
                    .lineLimit(1).padding(.horizontal, 25).padding(.top, 5)
            }
            HStack {
                Text("⌥Tab neste · ⇧Tab forrige · piltaster · mus")
                Spacer()
                Text("⌥Q ta ut · Slipp ⌥ åpner · Esc avbryter")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 25).padding(.vertical, 13)
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.075, green: 0.085, blue: 0.095).opacity(0.90))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    private func tile(_ card: WindowCard) -> some View {
        let chosen = store.switcherSelectionID == card.id
        return Button { choose(card.id) } label: {
            VStack(spacing: 9) {
                Group {
                    if let url = store.iconURL(for: card) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 17).fill(appColor(card.appName).opacity(0.25))
                            .overlay(Text(String(card.appName.prefix(1))).font(.system(size: 35, weight: .medium)))
                    }
                }.frame(width: 66, height: 66)
                Text(card.name).font(.system(size: 11, weight: chosen ? .semibold : .regular))
                    .lineLimit(2).multilineTextAlignment(.center).frame(height: 30, alignment: .top)
            }
            .frame(width: 112, height: 112)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(chosen ? .white.opacity(0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(chosen ? accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .background(SwitcherPointerTarget { store.selectWindowSwitcher(card.id, fromPointer: true) })
        .accessibilityLabel("\(card.name), \(card.appName)")
        .accessibilityValue(chosen ? "Valgt" : "")
    }
}

// Only actual mouseMoved events select a card. A tile appearing under a
// stationary cursor (opening, scrolling, keyboard navigation or removal)
// must not override the keyboard selection. The view never captures clicks.
struct SwitcherPointerTarget: NSViewRepresentable {
    let select: () -> Void
    func makeNSView(context: Context) -> SwitcherPointerView { SwitcherPointerView(select: select) }
    func updateNSView(_ view: SwitcherPointerView, context: Context) { view.select = select }
}

final class SwitcherPointerView: NSView {
    var select: () -> Void
    private var tracking: NSTrackingArea?
    init(select: @escaping () -> Void) { self.select = select; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseMoved(with event: NSEvent) { select() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}
