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
    @Binding var entry: EntryRoute?
    @ViewBuilder var list: Content

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(maxWidth: .infinity)
            if showsPane {
                Divider()
                    .ignoresSafeArea()
                EntryPane(entry: $entry)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

/// The right-hand pane: the entry picked in the list, or a word on what goes here.
private struct EntryPane: View {
    @Binding var entry: EntryRoute?

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    // A fresh page for each entry, so one's state (scroll, On This Day) isn't
                    // carried into the next.
                    EntryDetailView(entryID: entry.id)
                        .id(entry.id)
                } else {
                    ContentUnavailableView {
                        Label("No entry open", icon: "slab-book")
                    } description: {
                        Text("Pick an entry on the left to read it here.")
                    }
                }
            }
            // The entry at the root of the pane has nothing to go back to: deleting it, or
            // "back" from an entry opened over it, closes the pane instead.
            .environment(\.entryPane, EntryPaneClose { entry = nil })
        }
    }
}

/// How an entry at the root of the entry pane closes it (in place of a Back that has nowhere to go).
struct EntryPaneClose: Sendable {
    let close: @MainActor () -> Void
}

extension EnvironmentValues {
    /// Set inside the entry pane (wide screens): see `EntryPaneLayout`.
    @Entry var entryPane: EntryPaneClose? = nil
}

/// Where a list sends an entry it opens: the pane beside it on a wide screen, or a push onto its
/// navigation stack otherwise. Folding and unfolding move an open entry between the two, so it
/// stays open across the change.
struct EntryPaneRouting {
    /// The entry in the pane (wide screens).
    var paneEntry: EntryRoute?
    /// The entry this pushed onto the stack, while it's the only page there, so unfolding can
    /// move it into the pane.
    private(set) var pushed: EntryRoute?

    /// Opens `route` in the pane, or pushes it onto `path`.
    mutating func open(_ route: EntryRoute, wide: Bool, path: inout NavigationPath) {
        if wide {
            paneEntry = route
        } else {
            path.append(route)
            pushed = path.count == 1 ? route : nil
        }
    }

    /// An entry was deleted (from its row's menu, say): it's no longer the one to show.
    mutating func entryDeleted(_ id: Int?) {
        guard let id else { return }
        if paneEntry?.id == id { paneEntry = nil }
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
            paneEntry = pushed
        } else if let paneEntry {
            self.paneEntry = nil
            path.append(paneEntry)
            pushed = path.count == 1 ? paneEntry : nil
        }
    }
}
