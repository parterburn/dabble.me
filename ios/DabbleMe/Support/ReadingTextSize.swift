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

    /// The default is a touch under the body size, and the others are close around it: 90%,
    /// 95%, 99%, 105%, 110%.
    var scale: CGFloat {
        switch self {
        case .smallest: 0.90
        case .smaller: 0.95
        case .standard: 0.99
        case .larger: 1.05
        case .largest: 1.10
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

    /// The old scale's sizes, by the number each was stored as: Small, Default, Large, Extra
    /// Large, Largest.
    private static let legacyScales: [CGFloat] = [0.92, 1, 1.08, 1.16, 1.24]

    /// The stop nearest in size to one chosen on the old scale: Small becomes Smallest, Default
    /// stays Default, and the old three larger ones all become Largest (the new scale stops
    /// at 110%).
    static func migrated(fromLegacy raw: Int) -> ReadingTextSize {
        guard legacyScales.indices.contains(raw) else { return .standard }
        let old = legacyScales[raw]
        return allCases.min { abs($0.scale - old) < abs($1.scale - old) } ?? .standard
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
