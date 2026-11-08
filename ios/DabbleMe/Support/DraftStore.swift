import Foundation

/// Unsaved entries, so writing survives the app closing or crashing. Kept on this device only,
/// with complete file protection (unreadable while the phone is locked), and cleared on save,
/// discard, or sign out.
enum DraftStore {
    struct Draft: Codable, Equatable {
        var blocks: [DocumentBlock]
        /// YYYY-MM-DD for new entries.
        var date: String?
        var savedAt: Date
    }

    static func key(forEntry id: Int?) -> String {
        id.map { "entry-\($0)" } ?? "new"
    }

    static func load(_ key: String) -> Draft? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    static func save(_ draft: Draft, key: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: key), options: [.atomic, .completeFileProtection])
    }

    static func clear(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Drafts", directoryHint: .isDirectory)
    }

    private static func url(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }
}
