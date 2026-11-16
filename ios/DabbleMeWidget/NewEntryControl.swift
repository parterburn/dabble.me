import AppIntents
import SwiftUI
import WidgetKit

/// A control for Control Center, the Lock Screen and the Action button: New Entry. A tap opens
/// the app on the composer (`NewEntryIntent`).
struct NewEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "me.dabble.ios.control.new-entry") {
            ControlWidgetButton(action: NewEntryIntent()) {
                Label("New Entry", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Entry")
        .description("Opens Dabble Me to write. In the morning it's yesterday's entry, if you haven't written it; otherwise today's.")
    }
}
