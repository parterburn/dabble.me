import CoreGraphics

/// How large entry text is when reading (not editing). Multiplies the Dynamic Type body
/// size, so it adds to the user's system text size rather than replacing it.
enum ReadingTextSize: Int, CaseIterable, Identifiable {
    case small, standard, large, extraLarge, largest

    static let storageKey = "readingTextSize"

    var id: Int { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: 0.88
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.3
        case .largest: 1.5
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .largest: "Largest"
        }
    }

    var smaller: ReadingTextSize? { ReadingTextSize(rawValue: rawValue - 1) }
    var larger: ReadingTextSize? { ReadingTextSize(rawValue: rawValue + 1) }
}
