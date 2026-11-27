import SwiftUI
import Testing
@testable import DabbleMe

/// Where the Journal and Search send an opened entry: beside the list on a wide screen (iPhone Duo
/// open, iPad), pushed over it otherwise, and moved between the two when the phone folds or unfolds.
struct EntryPaneRoutingTests {
    @Test func wideOpensInThePane() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 1), wide: true, path: &path)
        #expect(routing.paneEntry == EntryRoute(id: 1))
        #expect(path.isEmpty)
    }

    @Test func narrowPushes() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 1), wide: false, path: &path)
        #expect(routing.paneEntry == nil)
        #expect(path.count == 1)
    }

    @Test func foldingMovesThePaneEntryOntoTheStack() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 7), wide: true, path: &path)
        routing.widthChanged(wide: false, path: &path)
        #expect(routing.paneEntry == nil)
        #expect(path.count == 1)
        // And back: unfolding puts it beside the list again.
        routing.widthChanged(wide: true, path: &path)
        #expect(routing.paneEntry == EntryRoute(id: 7))
        #expect(path.isEmpty)
    }

    @Test func unfoldingMovesAPushedEntryIntoThePane() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 3), wide: false, path: &path)
        routing.widthChanged(wide: true, path: &path)
        #expect(routing.paneEntry == EntryRoute(id: 3))
        #expect(path.isEmpty)
    }

    @Test func unfoldingLeavesADeeperStackAlone() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 3), wide: false, path: &path)
        routing.open(EntryRoute(id: 4), wide: false, path: &path)
        routing.widthChanged(wide: true, path: &path)
        #expect(routing.paneEntry == nil)
        #expect(path.count == 2)
    }

    @Test func goingBackForgetsThePushedEntry() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 3), wide: false, path: &path)
        path.removeLast()
        routing.pathChanged(count: path.count)
        // A page pushed some other way isn't taken for the entry.
        path.append(EntryRoute(id: 9))
        routing.pathChanged(count: path.count)
        routing.widthChanged(wide: true, path: &path)
        #expect(routing.paneEntry == nil)
        #expect(path.count == 1)
    }

    @Test func deletingTheOpenEntryClosesThePane() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.open(EntryRoute(id: 5), wide: true, path: &path)
        routing.entryDeleted(6)
        #expect(routing.paneEntry == EntryRoute(id: 5))
        routing.entryDeleted(5)
        #expect(routing.paneEntry == nil)
    }

    @Test func foldingWithNothingOpenChangesNothing() {
        var routing = EntryPaneRouting()
        var path = NavigationPath()
        routing.widthChanged(wide: false, path: &path)
        routing.widthChanged(wide: true, path: &path)
        #expect(routing.paneEntry == nil)
        #expect(path.isEmpty)
    }
}
