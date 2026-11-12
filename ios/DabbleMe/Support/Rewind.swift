import Foundation
import NaturalLanguage

/// When the year's Rewind is offered (Stats, PRO): November and December for the year so far, and
/// January for the year just ended, once that year has a few entries.
enum RewindSeason {
    static let minimumEntries = 5

    /// The year to look back on as of `day`, or nil outside the season.
    static func year(on day: JournalDay) -> Int? {
        let parts = day.iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        #if DEBUG
        // UI tests and screenshots, any time of year: -DabbleDebugRewindYear 2026.
        let forced = UserDefaults.standard.integer(forKey: "DabbleDebugRewindYear")
        if forced > 0 { return forced }
        #endif
        switch parts[1] {
        case 11, 12: return parts[0]
        case 1: return parts[0] - 1
        default: return nil
        }
    }
}

/// A year of the journal, worked out on the device for its Rewind: counts, the people and places
/// its entries name (Apple's on-device name recognition, no Apple Intelligence needed), songs,
/// hashtags and photos. `build` does the work; everything else is the result.
struct Rewind: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let id: Int
        let day: JournalDay
        /// The entry's words, without Markdown or links to songs.
        let text: String
        let words: Int
        let imageUrl: String?
        let hashtags: [String]
        let songs: [Song]

        var thumbnail: URL? { EntrySummary.thumbnailURL(imageUrl, width: 600) }
    }

    /// A person or place the entries name, and the entries that do.
    struct Mention: Equatable, Sendable, Identifiable {
        let name: String
        let entryIDs: [Int]
        let firstDay: JournalDay

        var id: String { name.lowercased() }
        var count: Int { entryIDs.count }
    }

    struct Gap: Equatable, Sendable {
        let days: Int
        let from: JournalDay
        let to: JournalDay
    }

    struct Milestone: Equatable, Sendable, Identifiable {
        let tag: String
        let years: Int

        var id: String { tag.lowercased() }
    }

    let year: Int
    /// Oldest first.
    let entries: [Entry]
    let wordCount: Int
    /// "Saturday", and how many entries fell on it.
    let busiestWeekday: (name: String, count: Int)?
    /// 1–12, and its entries.
    let biggestMonth: (month: Int, count: Int)?
    /// The longest stretch between two entries, when it's a week or more.
    let longestGap: Gap?
    /// Who the entries name most (in at least two), most first.
    let people: [Mention]
    /// Where they name, in the order they first come up.
    let places: [Mention]
    let songs: [(song: Song, day: JournalDay)]
    let hashtags: [HashtagCount]
    /// Dated #tags used this year, and how many years on from their date it is.
    let milestones: [Milestone]

    var photos: [Entry] { entries.filter { $0.imageUrl != nil } }
    var days: Set<String> { Set(entries.map(\.day.iso)) }
    var averageWords: Int { entries.isEmpty ? 0 : Int((Double(wordCount) / Double(entries.count)).rounded()) }
    /// "January to November": the months the entries span.
    var span: String {
        guard let first = entries.first?.day, let last = entries.last?.day else { return String(year) }
        let from = first.formatted(.dateTime.month(.wide)), to = last.formatted(.dateTime.month(.wide))
        return from == to ? from : "\(from) to \(to)"
    }

    func entries(inMonth month: Int) -> [Entry] {
        entries.filter { Int($0.day.iso.dropFirst(5).prefix(2)) == month }
    }

    func entries(mentioning mention: Mention) -> [Entry] {
        let ids = Set(mention.entryIDs)
        return entries.filter { ids.contains($0.id) }
    }

    static func monthName(_ month: Int) -> String {
        JournalDay(String(format: "2000-%02d-01", month))?.formatted(.dateTime.month(.wide)) ?? ""
    }

    static func == (lhs: Rewind, rhs: Rewind) -> Bool {
        lhs.year == rhs.year && lhs.entries == rhs.entries && lhs.people == rhs.people && lhs.places == rhs.places
    }

    // MARK: - Building it

    /// Works the year out from its entries. Names take a moment to find, so this is called off
    /// the main thread. `ownName` (the writer's first name) isn't counted among the people.
    static func build(year: Int, summaries: [EntrySummary], ownName: String?, tagDates: [TagDate]) -> Rewind {
        let entries: [Entry] = summaries.compactMap { summary -> Entry? in
            guard let day = summary.day, day.iso.hasPrefix("\(year)-") else { return nil }
            let text = plainText(summary.previewText ?? summary.excerpt)
            return Entry(id: summary.id, day: day, text: text, words: summary.wordCount ?? wordCount(in: text),
                         imageUrl: summary.imageProcessing ? nil : summary.imageUrl, hashtags: summary.hashtags, songs: summary.songs ?? [])
        }.sorted { $0.day < $1.day }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        // The day written on most (the earlier in the week, on a tie).
        let byWeekday = Dictionary(grouping: entries) { utc.component(.weekday, from: $0.day.date) }
        let weekday = byWeekday.max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }
            .map { ($0.value[0].day.formatted(.dateTime.weekday(.wide)), $0.value.count) }
        let byMonth = Dictionary(grouping: entries) { Int($0.day.iso.dropFirst(5).prefix(2)) ?? 0 }
        let month = byMonth.max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }.map { ($0.key, $0.value.count) }

        var gap: Gap?
        for (earlier, later) in zip(entries, entries.dropFirst()) {
            let days = utc.dateComponents([.day], from: earlier.day.date, to: later.day.date).day ?? 0
            if days >= 7, days > (gap?.days ?? 0) { gap = Gap(days: days, from: earlier.day, to: later.day) }
        }

        let names = mentions(in: entries, ownName: ownName)
        var seenSongs = Set<URL>()
        let songs = entries.flatMap { entry in entry.songs.map { (song: $0, day: entry.day) } }
            .filter { seenSongs.insert($0.song.spotifyUrl).inserted }

        var spelling: [String: String] = [:], counts: [String: Int] = [:]
        for entry in entries {
            for tag in Set(entry.hashtags.map { $0.lowercased() }) { counts[tag, default: 0] += 1 }
            for tag in entry.hashtags { spelling[tag.lowercased()] = tag } // the latest spelling
        }
        let hashtags = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { HashtagCount(tag: spelling[$0.key] ?? $0.key, count: $0.value) }
        let milestones = tagDates.compactMap { tag -> Milestone? in
            guard counts[tag.tag.lowercased()] != nil, let from = Int(tag.date.prefix(4)), year > from else { return nil }
            return Milestone(tag: spelling[tag.tag.lowercased()] ?? tag.tag, years: year - from)
        }.sorted { $0.years > $1.years }

        return Rewind(year: year, entries: entries, wordCount: entries.reduce(0) { $0 + $1.words }, busiestWeekday: weekday,
                      biggestMonth: month, longestGap: gap, people: names.people, places: names.places, songs: songs,
                      hashtags: hashtags, milestones: milestones)
    }

    /// Light Markdown to plain words: emphasis marks go, a link keeps its text, links to songs go
    /// (the songs have a slide of their own).
    static func plainText(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"\[?https?://open\.spotify\.com/\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(\*\*|__|\*|_)(?=\S)(.+?)(?<=\S)\1"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace }.count(where: { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) })
    }

    /// The people and places the entries name, each counted once per entry. A person goes by
    /// their first name ("Leo" and "Leo Smith" are the same Leo), and needs two entries to count.
    static func mentions(in entries: [Entry], ownName: String?) -> (people: [Mention], places: [Mention]) {
        var people: [String: (name: String, ids: [Int], first: JournalDay)] = [:]
        var places: [String: (name: String, ids: [Int], first: JournalDay)] = [:]
        let own = ownName?.lowercased()
        let tagger = NLTagger(tagSchemes: [.nameType])
        for entry in entries {
            // "#Leo" is Leo to the tagger without its "#".
            let text = entry.text.replacingOccurrences(of: "#", with: "")
            tagger.string = text
            var seenPeople = Set<String>(), seenPlaces = Set<String>()
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tag == .personalName, let first = token.split(separator: " ").first.map(String.init),
                   first.count >= 2, first.first?.isUppercase == true, first.lowercased() != own {
                    let name = first.hasSuffix("'s") || first.hasSuffix("’s") ? String(first.dropLast(2)) : first
                    if seenPeople.insert(name.lowercased()).inserted {
                        people[name.lowercased(), default: (name, [], entry.day)].ids.append(entry.id)
                    }
                } else if tag == .placeName, token.count >= 3, token.first?.isUppercase == true {
                    if seenPlaces.insert(token.lowercased()).inserted {
                        places[token.lowercased(), default: (token, [], entry.day)].ids.append(entry.id)
                    }
                }
                return true
            }
        }
        // Where name recognition has nothing to offer at all (it isn't on every device, or in the
        // simulator), names are found by their capitals instead; places can't be told that way.
        if people.isEmpty, places.isEmpty {
            // A name is known from anywhere it's capitalized mid-sentence, then counted wherever
            // it's written, the start of a sentence included.
            // A word that's also written small somewhere ("The … the") is a word, not a name.
            let small = Set(entries.flatMap { $0.text.split { !$0.isLetter && $0 != "'" && $0 != "’" } }
                .filter { $0.first?.isLowercase == true }.map { $0.lowercased() })
            let known = Set(entries.flatMap { capitalizedNames(in: $0.text) }.map { $0.lowercased() }).subtracting(small)
            for entry in entries {
                var seen = Set<String>()
                for raw in entry.text.split(whereSeparator: \.isWhitespace) {
                    var word = raw.trimmingCharacters(in: CharacterSet.letters.inverted)
                    if word.hasSuffix("'s") || word.hasSuffix("’s") { word = String(word.dropLast(2)) }
                    let key = word.lowercased()
                    guard word.first?.isUppercase == true, known.contains(key), key != own, seen.insert(key).inserted else { continue }
                    people[key, default: (word, [], entry.day)].ids.append(entry.id)
                }
            }
        }
        let ranked = people.values.filter { $0.ids.count >= 2 }
            .sorted { ($0.ids.count, $1.name) > ($1.ids.count, $0.name) }
            .map { Mention(name: $0.name, entryIDs: $0.ids, firstDay: $0.first) }
        // A name that's also someone (a "Georgia" who shows up most) isn't listed as a place.
        let who = Set(ranked.map { $0.name.lowercased() })
        let where_ = places.values.filter { !who.contains($0.name.lowercased()) }
            .sorted { ($0.first, $0.name) < ($1.first, $1.name) }
            .map { Mention(name: $0.name, entryIDs: $0.ids, firstDay: $0.first) }
        return (ranked, where_)
    }

    /// Words that are capitalized where a sentence doesn't call for it (or are #Tags), once each:
    /// most likely names. Months, weekdays and "I" aren't.
    static func capitalizedNames(in text: String) -> [String] {
        let skipped: Set<String> = ["i", "i'm", "i'll", "i've", "i'd", "january", "february", "march", "april", "may", "june", "july",
                                    "august", "september", "october", "november", "december", "monday", "tuesday", "wednesday",
                                    "thursday", "friday", "saturday", "sunday", "christmas", "thanksgiving", "halloween", "easter"]
        var names: [String] = []
        var seen = Set<String>()
        // A new line starts a sentence too (a list item, a heading).
        for line in text.split(whereSeparator: \.isNewline) {
        var startsSentence = true
        for raw in line.split(whereSeparator: \.isWhitespace) {
            let isTag = raw.hasPrefix("#")
            var word = raw.trimmingCharacters(in: CharacterSet.letters.inverted)
            if word.hasSuffix("'s") || word.hasSuffix("’s") { word = String(word.dropLast(2)) }
            let ends = raw.last.map { ".!?:".contains($0) } ?? false
            defer { startsSentence = ends }
            guard word.count >= 2, word.first?.isUppercase == true, word.dropFirst().allSatisfy(\.isLowercase),
                  isTag || !startsSentence, !skipped.contains(word.lowercased().replacingOccurrences(of: "’", with: "'")),
                  seen.insert(word.lowercased()).inserted else { continue }
            names.append(word)
        }
        }
        return names
    }

    // MARK: - Line of the year

    /// Sentences from the year that could be its "line of the year": in the writer's own voice,
    /// a comfortable length, the ones that sound most like taking stock first. Apple Intelligence
    /// picks among them by number, so what's shown is always the writer's own words.
    func lineCandidates(limit: Int = 20) -> [(text: String, day: JournalDay)] {
        let warm = ["grateful", "thankful", "love", "loved", "proud", "best", "never", "always", "remember", "realized",
                    "realize", "learned", "feel", "felt", "happy", "lucky", "home", "life", "enough", "worth", "miss", "hope"]
        var found: [(text: String, day: JournalDay, score: Int)] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        for entry in entries {
            tokenizer.string = entry.text
            tokenizer.enumerateTokens(in: entry.text.startIndex..<entry.text.endIndex) { range, _ in
                let sentence = entry.text[range].trimmingCharacters(in: .whitespacesAndNewlines)
                let words = sentence.lowercased().split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
                guard (8...36).contains(words.count), !sentence.contains("\n"), !sentence.contains("#"),
                      words.contains(where: { ["i", "we", "my", "our", "i'm", "i’m", "i've", "i’ve"].contains($0) }) else { return true }
                let score = words.count(where: { warm.contains($0) })
                if score > 0 { found.append((sentence, entry.day, score)) }
                return true
            }
        }
        return found.sorted { ($0.score, $0.text.count) > ($1.score, $1.text.count) }.prefix(limit).map { ($0.text, $0.day) }
    }
}

/// The lines Apple Intelligence adds to a Rewind, written on the device and kept for the year
/// (redone when the year's entries change). Each is optional: a slide simply goes without.
struct RewindStory: Codable, Equatable, Sendable {
    /// What the biggest month held, in a sentence.
    var monthCaption: String?
    /// A phrase for each of the people named most, by lowercased name.
    var peopleCaptions: [String: String] = [:]
    /// The line of the year (the writer's own sentence) and its day (YYYY-MM-DD).
    var line: String?
    var lineDay: String?
    /// The year in a few words (six are asked for).
    var sixWords: String?

    private static func storageKey(_ year: Int) -> String { "rewind.story.\(year)" }

    private struct Saved: Codable {
        let key: String
        let story: RewindStory
    }

    /// The story kept for this year, if its entries haven't changed since.
    static func saved(for rewind: Rewind) -> RewindStory? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(rewind.year)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.key == key(for: rewind) else { return nil }
        return saved.story
    }

    func save(for rewind: Rewind) {
        guard let data = try? JSONEncoder().encode(Saved(key: Self.key(for: rewind), story: self)) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey(rewind.year))
    }

    private static func key(for rewind: Rewind) -> String {
        "3|\(rewind.entries.count)|\(rewind.wordCount)|\(rewind.entries.last?.id ?? 0)|\(rewind.people.prefix(3).map(\.id).joined(separator: ","))"
    }
}
