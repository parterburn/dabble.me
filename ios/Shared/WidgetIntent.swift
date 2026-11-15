import AppIntents
import WidgetKit

/// What one widget shows next to today's date, chosen on the widget itself (touch and hold it,
/// Edit Widget). Left on "Same as in the App", it follows Settings → Home Screen Widget.
enum WidgetShowOption: String, AppEnum {
    case appSetting, prompt, promptEntry, memoryCount, memoryEntry

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "What Shows"

    static let caseDisplayRepresentations: [WidgetShowOption: DisplayRepresentation] = [
        .appSetting: "Same as in the App",
        .prompt: "A Prompt for You",
        .promptEntry: "A Prompt, Then Today's Entry",
        .memoryCount: "Rewind",
        .memoryEntry: "Rewind, With the Entry",
    ]

    /// This widget's own choice, or nil to go by the app's setting.
    var content: WidgetContent? {
        switch self {
        case .appSetting: nil
        case .prompt: .prompt
        case .promptEntry: .promptEntry
        case .memoryCount: .memoryCount
        case .memoryEntry: .memoryEntry
        }
    }
}

struct TodayWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Today"
    static let description = IntentDescription("What the widget shows next to today's date. The ones with an entry put its first lines, and its photo, on your Home Screen.")

    @Parameter(title: "Next to Today's Date", default: .appSetting)
    var show: WidgetShowOption
}
