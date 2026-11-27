import SwiftUI

/// On a wide screen (iPhone Duo open, an iPad), the Journal and Search open entries beside their
/// list rather than over it: the list on the left, the entry on the right, split down the middle
/// so the Duo's fold falls between the two and through neither. On a narrow screen (Duo closed,
/// any other iPhone, iPad Split View) it's the list alone, and entries push over it as before.
///
/// The list keeps its place in the layout either way (it's always the first child), so folding
/// or unfolding doesn't rebuild it: its scroll position and navigation survive.
struct EntryPaneLayout<Content: View>: View {
    /// The entry pane is showing (wide, and a view of the list that opens entries).
    let showsPane: Bool
    @Binding var routing: EntryPaneRouting
    @ViewBuilder var list: Content

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(maxWidth: .infinity)
            if showsPane {
                Divider()
                    .ignoresSafeArea()
                EntryPane(routing: $routing)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

/// The right-hand pane: the entry picked in the list, or a word on what goes here.
private struct EntryPane: View {
    @Binding var routing: EntryPaneRouting

    var body: some View {
        NavigationStack {
            Group {
                if let entry = routing.paneEntry {
                    // A fresh page each time a row is picked (the same row again too, after
                    // swiping to a neighbouring day), so one's state isn't carried into the next.
                    EntryDetailView(entryID: entry.id)
                        .id(routing.opening)
                } else {
                    ContentUnavailableView {
                        Label("No entry open", icon: "slab-book")
                    } description: {
                        Text("Pick an entry on the left to read it here.")
                    }
                }
            }
            // The entry at the root of the pane has nothing to go back to: deleting it, or
            // "back" from an entry opened over it, closes the pane instead. Swiping its title
            // to another day says which one it now shows.
            .environment(\.entryPane, EntryPaneLink(close: { routing.closePane() },
                                                    showing: { routing.showing($0) }))
        }
    }
}

/// How the entry at the root of the entry pane talks back to it: closing it (in place of a Back
/// that has nowhere to go), and saying which entry it shows after a swipe to another day.
struct EntryPaneLink: Sendable {
    let close: @MainActor () -> Void
    let showing: @MainActor (Int) -> Void
}

extension EnvironmentValues {
    /// Set inside the entry pane (wide screens): see `EntryPaneLayout`.
    @Entry var entryPane: EntryPaneLink? = nil
}

/// Where a list sends an entry it opens: the pane beside it on a wide screen, or a push onto its
/// navigation stack otherwise. Folding and unfolding move an open entry between the two, so it
/// stays open across the change.
struct EntryPaneRouting {
    /// The entry the pane opened with (wide screens).
    private(set) var paneEntry: EntryRoute?
    /// Counts pane openings: a new page for each.
    private(set) var opening = 0
    /// The entry the pane shows now, when a swipe has moved it on from `paneEntry`.
    private var shownID: Int?
    /// The entry this pushed onto the stack, while it's the only page there, so unfolding can
    /// move it into the pane.
    private(set) var pushed: EntryRoute?

    /// The entry the pane shows (for its row's tint, and to carry over when folding).
    var openID: Int? { paneEntry == nil ? nil : shownID ?? paneEntry?.id }

    /// Opens `route` in the pane, or pushes it onto `path`.
    mutating func open(_ route: EntryRoute, wide: Bool, path: inout NavigationPath) {
        if wide {
            showInPane(route)
        } else {
            path.append(route)
            pushed = path.count == 1 ? route : nil
        }
    }

    /// The pane's entry swiped to another day.
    mutating func showing(_ id: Int) {
        if paneEntry != nil { shownID = id }
    }

    mutating func closePane() {
        paneEntry = nil
        shownID = nil
    }

    /// An entry was deleted (from its row's menu, say): it's no longer the one to show.
    mutating func entryDeleted(_ id: Int?) {
        guard let id else { return }
        if openID == id { closePane() }
        if pushed?.id == id { pushed = nil }
    }

    /// The stack's depth changed (Back, or a page pushed by a link this didn't open).
    mutating func pathChanged(count: Int) {
        if count != 1 { pushed = nil }
    }

    /// The screen went wide or narrow: the open entry moves to where it now belongs.
    mutating func widthChanged(wide: Bool, path: inout NavigationPath) {
        if wide {
            // Only the entry this pushed, with nothing over it: an entry opened from another's
            // On This Day keeps its stack.
            guard let pushed, path.count == 1 else { return }
            path = NavigationPath()
            self.pushed = nil
            showInPane(pushed)
        } else if let id = openID {
            closePane()
            let route = EntryRoute(id: id)
            path.append(route)
            pushed = path.count == 1 ? route : nil
        }
    }

    private mutating func showInPane(_ route: EntryRoute) {
        paneEntry = route
        shownID = nil
        opening += 1
    }
}
