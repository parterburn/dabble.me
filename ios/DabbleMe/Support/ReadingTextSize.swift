import SwiftUI
import UIKit

/// How large entry text is when reading (not editing). Multiplies the Dynamic Type body
/// size, so it adds to the user's system text size rather than replacing it.
enum ReadingTextSize: Int, CaseIterable, Identifiable {
    /// Five stops with the default in the middle: two smaller, two larger.
    case smallest, smaller, standard, larger, largest

    /// (A new key with these stops: the old ones, under `legacyStorageKey`, had the default
    /// second of five and other sizes. See `migrateStoredSize`.)
    static let storageKey = "entryTextSize"
    static let legacyStorageKey = "readingTextSize"

    var id: Int { rawValue }

    /// The default is a touch under the body size (99%), and each stop is 9 points of a
    /// hundred from the next: 81%, 90%, 99%, 108%, 117%.
    var scale: CGFloat {
        switch self {
        case .smallest: 0.81
        case .smaller: 0.90
        case .standard: 0.99
        case .larger: 1.08
        case .largest: 1.17
        }
    }

    var label: String {
        switch self {
        case .smallest: "Smallest"
        case .smaller: "Smaller"
        case .standard: "Default"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    /// The stop nearest in size to one chosen on the old scale (Small 92%, Default 100%, Large
    /// 108%, Extra Large 116%, Largest 124%, numbered from 0): one stop along, since the default
    /// moved from second to third, and the old two largest both become Largest.
    static func migrated(fromLegacy raw: Int) -> ReadingTextSize {
        ReadingTextSize(rawValue: min(max(raw + 1, 0), allCases.count - 1)) ?? .standard
    }

    /// Once, at launch: a size chosen before the stops changed is carried over to the nearest
    /// new one, so nobody's text jumps. Someone who never chose gets the new default.
    static func migrateStoredSize(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil, let old = defaults.object(forKey: legacyStorageKey) as? Int else { return }
        defaults.set(migrated(fromLegacy: old).rawValue, forKey: storageKey)
    }

    var nextSmaller: ReadingTextSize? { ReadingTextSize(rawValue: rawValue - 1) }
    var nextLarger: ReadingTextSize? { ReadingTextSize(rawValue: rawValue + 1) }
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
