import Foundation
import UIKit

/// A moment picked from Apple's Journaling Suggestions ("Moments from your iPhone", in the
/// composer's Writing ideas), reduced to what an entry takes from it: its title as a heading,
/// a line of text for each place, workout, song, person and so on (every plan), and its photos
/// (PRO, like any photo). Apple's own types stay in `MomentPicker`; this is plain values, so
/// the text can be tested where the framework isn't (the simulator has none).
struct Moment: Equatable, Sendable {
    var title: String
    var places: [Place] = []
    var workouts: [Workout] = []
    var songs: [Track] = []
    var podcasts: [Track] = []
    /// Other listening (an audiobook, a song in another app).
    var media: [Track] = []
    var people: [String] = []
    /// "Pleasant", "Very unpleasant"… from a State of Mind logged in Health.
    var feelings: [String] = []
    var steps: Int?
    var events: [String] = []
    /// Apple's own questions to write about: added like the composer's prompts.
    var reflections: [String] = []
    /// The photos, already read and prepared (Apple's files only last as long as the picker's
    /// answer). Only filled when the account can add photos.
    var photos: [PreparedPhoto] = []
    /// How many photos the moment had, kept or not: a free account is told photos are PRO.
    var photoCount = 0

    struct Place: Equatable, Sendable {
        var place: String?
        var city: String?
    }

    struct Workout: Equatable, Sendable {
        var name: String?
        var meters: Double?
        var seconds: TimeInterval?
    }

    struct Track: Equatable, Sendable {
        var title: String?
        var by: String?
    }

    /// Journaling Suggestions is iPhone-only, and the simulator has no framework for it.
    @MainActor static var isAvailable: Bool {
        #if canImport(JournalingSuggestions)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// The moment's title, unless it says nothing the lines below it don't.
    var heading: String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// One line per thing, in the order a day is remembered: where, what was done, who with,
    /// what was playing, how it felt. Repeats (an item offered two ways) go in once.
    func lines(locale: Locale = .current) -> [String] {
        var lines: [String] = []
        for place in places {
            let parts = [place.place, place.city].compactMap(\.self).map(Self.trimmed).filter { !$0.isEmpty }
            let named = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !named.isEmpty { lines.append("📍 " + named.joined(separator: ", ")) }
        }
        for workout in workouts {
            var parts = [workout.name.map(Self.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? "Workout"]
            if let meters = workout.meters, meters > 0 {
                parts.append(Measurement(value: meters, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale)))
            }
            if let seconds = workout.seconds, seconds >= 60 {
                parts.append(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)))
            }
            lines.append("🏃 " + parts.joined(separator: " · "))
        }
        if let steps, steps > 0 {
            lines.append("👣 \(steps.formatted(.number.locale(locale))) steps")
        }
        let people = people.map(Self.trimmed).filter { !$0.isEmpty }
        if !people.isEmpty {
            lines.append("👥 With " + people.formatted(.list(type: .and).locale(locale)))
        }
        for event in events.map(Self.trimmed) where !event.isEmpty {
            lines.append("🎟️ " + event)
        }
        for song in songs { if let line = Self.line("🎶", by: song.by, title: song.title) { lines.append(line) } }
        for podcast in podcasts { if let line = Self.line("🎧", by: podcast.by, title: podcast.title) { lines.append(line) } }
        for item in media { if let line = Self.line("🎵", by: item.by, title: item.title) { lines.append(line) } }
        for feeling in feelings.map(Self.trimmed) where !feeling.isEmpty {
            lines.append("💭 Felt " + feeling.lowercased())
        }
        return lines.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// "Artist – Title", or whichever of the two there is.
    private static func line(_ mark: String, by: String?, title: String?) -> String? {
        let parts = [by, title].compactMap(\.self).map(trimmed).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : "\(mark) " + parts.joined(separator: " – ")
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
