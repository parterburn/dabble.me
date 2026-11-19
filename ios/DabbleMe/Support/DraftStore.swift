import Foundation

/// Unsaved entries, so writing survives the app closing or crashing. Kept on this device only,
/// with complete file protection (unreadable while the phone is locked), and cleared on save,
/// discard, or sign out. A draft keeps its photos too: the prepared JPEGs (already downscaled,
/// with no location) in a folder beside it, and whether the entry's own photo was removed.
enum DraftStore {
    struct Draft: Codable, Equatable {
        var blocks: [DocumentBlock]
        /// The words as they were typed (`RichText.typedRuns`), blank lines and empty list items
        /// included: what's put back, so a template's unfilled places aren't lost with the app
        /// closing. (Drafts kept before this have only their blocks.)
        var typed: [DocumentRun]?
        /// YYYY-MM-DD for new entries.
        var date: String?
        var savedAt: Date
        /// The photos added, in order: names of files in the draft's photo folder (`savePhotos`).
        var photos: [String]? = nil
        /// Editing: the entry's own photo was removed.
        var removesPhoto: Bool? = nil
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
        try? FileManager.default.removeItem(at: photoDirectory(for: key))
    }

    /// Keeps these photos with the draft: each written once (a file already there is left as it
    /// is), and any no longer among them removed.
    static func savePhotos(_ photos: [(name: String, photo: PreparedPhoto)], key: String) {
        let folder = photoDirectory(for: key)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var kept: Set<String> = []
        for (name, photo) in photos {
            let full = folder.appending(path: "\(name).jpg"), thumb = folder.appending(path: "\(name)-thumb.jpg")
            kept.formUnion([full.lastPathComponent, thumb.lastPathComponent])
            if !fileManager.fileExists(atPath: full.path) { try? photo.data.write(to: full, options: [.atomic, .completeFileProtection]) }
            if !fileManager.fileExists(atPath: thumb.path) { try? photo.thumbnail.write(to: thumb, options: [.atomic, .completeFileProtection]) }
        }
        for file in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where !kept.contains(file) {
            try? fileManager.removeItem(at: folder.appending(path: file))
        }
        if photos.isEmpty { try? fileManager.removeItem(at: folder) }
    }

    /// The draft's photos, in order; any whose files are gone are left out.
    static func loadPhotos(_ names: [String], key: String) -> [(name: String, photo: PreparedPhoto)] {
        let folder = photoDirectory(for: key)
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: folder.appending(path: "\(name).jpg")),
                  let thumbnail = try? Data(contentsOf: folder.appending(path: "\(name)-thumb.jpg")) else { return nil }
            return (name, PreparedPhoto(data: data, contentType: "image/jpeg", filename: "photo.jpg", thumbnail: thumbnail))
        }
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

    private static func photoDirectory(for key: String) -> URL {
        directory.appending(path: "\(key)-photos", directoryHint: .isDirectory)
    }
}
