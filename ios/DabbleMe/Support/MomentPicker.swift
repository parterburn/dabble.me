#if canImport(JournalingSuggestions)
import Foundation
import HealthKit
import JournalingSuggestions

/// Apple's Journaling Suggestions answer, turned into a `Moment`. Only what the person picked in
/// Apple's sheet reaches the app, and only this once: its files are read here, before returning.
extension Moment {
    /// `photoLimit`: how many photos to read (0 on a free account, or with the entry full). They're
    /// counted either way.
    /// (On the main actor, where the picker hands it over.)
    @MainActor
    static func from(_ picked: JournalingSuggestion, photoLimit: Int) async -> Moment {
        // Apple's suggestion is a value nothing else holds, but isn't marked Sendable, so each
        // `content(forType:)` call would otherwise count as sharing it.
        nonisolated(unsafe) let suggestion = picked
        var moment = Moment(title: suggestion.title)
        moment.when = suggestion.date

        for location in await suggestion.content(forType: JournalingSuggestion.Location.self) {
            moment.places.append(Place(place: location.place, city: location.city))
        }
        for group in await suggestion.content(forType: JournalingSuggestion.LocationGroup.self) {
            moment.places += group.locations.map { Place(place: $0.place, city: $0.city) }
        }

        var workouts = await suggestion.content(forType: JournalingSuggestion.Workout.self)
        for group in await suggestion.content(forType: JournalingSuggestion.WorkoutGroup.self) {
            workouts += group.workouts
        }
        moment.workouts = workouts.map { workout in
            // (A workout's name, "Outdoor Walk", comes with iOS 26; before it, it's a "Workout".)
            var name: String?
            if #available(iOS 26.0, *) { name = workout.details?.localizedName }
            return Workout(name: name,
                           meters: workout.details?.distance?.doubleValue(for: .meter()),
                           seconds: workout.details?.date?.duration)
        }

        let steps = await suggestion.content(forType: JournalingSuggestion.MotionActivity.self).map(\.steps).reduce(0, +)
        moment.steps = steps > 0 ? steps : nil
        moment.people = await suggestion.content(forType: JournalingSuggestion.Contact.self).map(\.name)
        if #available(iOS 26.0, *) {
            moment.events = await suggestion.content(forType: JournalingSuggestion.EventPoster.self).map { String($0.title.characters) }
        }
        moment.songs = await suggestion.content(forType: JournalingSuggestion.Song.self).map { Track(title: $0.song, by: $0.artist) }
        moment.podcasts = await suggestion.content(forType: JournalingSuggestion.Podcast.self).map { Track(title: $0.episode, by: $0.show) }
        moment.media = await suggestion.content(forType: JournalingSuggestion.GenericMedia.self).map { Track(title: $0.title, by: $0.artist) }
        moment.feelings = await suggestion.content(forType: JournalingSuggestion.StateOfMind.self).compactMap { feeling(of: $0.state) }
        moment.reflections = await suggestion.content(forType: JournalingSuggestion.Reflection.self).map(\.prompt)

        // Photos, and a Live Photo's still. (Videos aren't something an entry holds.)
        let photoFiles = await suggestion.content(forType: JournalingSuggestion.Photo.self).map(\.photo)
            + suggestion.content(forType: JournalingSuggestion.LivePhoto.self).map(\.image)
        moment.photoCount = photoFiles.count
        // Off the main actor, one original at a time: each is read and prepared (at most 2400px,
        // no metadata) before the next, so only the prepared copies are held.
        let wanted = Array(photoFiles.prefix(max(photoLimit, 0)))
        if !wanted.isEmpty {
            moment.photos = await Task.detached(priority: .userInitiated) {
                wanted.compactMap { url in
                    autoreleasepool { (try? Data(contentsOf: url)).flatMap { try? PhotoPreparer.prepare($0) } }
                }
            }.value
        }
        return moment
    }

    private static func feeling(of state: HKStateOfMind) -> String? {
        switch state.valenceClassification {
        case .veryUnpleasant: "Very unpleasant"
        case .unpleasant: "Unpleasant"
        case .slightlyUnpleasant: "Slightly unpleasant"
        case .neutral: "Neutral"
        case .slightlyPleasant: "Slightly pleasant"
        case .pleasant: "Pleasant"
        case .veryPleasant: "Very pleasant"
        @unknown default: nil
        }
    }
}
#endif
