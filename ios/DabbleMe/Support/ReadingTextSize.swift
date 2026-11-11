import SwiftUI
import UIKit

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

/// Settings → Theme → Entry Font: entries in a serif (the default, like a page) or a
/// sans-serif, everywhere entry text appears.
enum ReadingFontStyle: String, CaseIterable, Identifiable {
    case serif, sansSerif

    static let storageKey = "readingFontStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .serif: "Serif"
        case .sansSerif: "Sans Serif"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sansSerif: .default
        }
    }

    /// For UIKit text (the editor).
    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .sansSerif: .default
        }
    }

    static var current: ReadingFontStyle {
        UserDefaults.standard.string(forKey: storageKey).flatMap(ReadingFontStyle.init) ?? .serif
    }
}

/// Settings → Theme: follow the system (Auto), or always Light or Dark. (The stored values keep
/// their first names.)
enum AppTheme: String, CaseIterable, Identifiable {
    case system, day, night

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Auto"
        case .day: "Light"
        case .night: "Dark"
        }
    }

    /// For `.preferredColorScheme`: nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .day: .light
        case .night: .dark
        }
    }
}
