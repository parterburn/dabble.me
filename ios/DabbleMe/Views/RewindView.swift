import SwiftUI

/// The year's Rewind: a look back at a year of the journal as a run of full-screen cards, tapped
/// through like a story (the right of the screen goes on, the left edge goes back). Counts, the
/// people and places named, songs, hashtags and photos are worked out on the device; with Apple
/// Intelligence on, a few lines are written there too (what the biggest month held, a phrase for
/// each person, the line of the year, the year in a few words) and kept for next time. Offered
/// from Stats in its season (`RewindSeason`), PRO.
struct RewindView: View {
    let year: Int
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rewind: Rewind?
    @State private var story = RewindStory()
    @State private var error: String?
    /// 0…1 while the year is read and (with Apple Intelligence) its lines written.
    @State private var progress = 0.0
    @State private var isWriting = false
    @State private var index = 0

    var body: some View {
        ZStack {
            if let rewind {
                cards(for: rewind)
            } else {
                loading
            }
        }
        .statusBarHidden()
        .task { await load() }
    }

    // MARK: - Loading

    private var loading: some View {
        ZStack {
            Tone.paper.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("\(String(year)) Rewind")
                    .font(.custom("InstrumentSerif-Regular", size: 54))
                    .foregroundStyle(Tone.paper.text)
                if let error {
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Tone.paper.text.opacity(0.7))
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                } else {
                    ProgressView(value: progress)
                        .tint(Color("AccentColor"))
                        .frame(width: 180)
                    Text(isWriting ? "Apple Intelligence is writing a few lines on your device…" : "Reading your year…")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Tone.paper.text.opacity(0.7))
                        .accessibilityIdentifier("RewindLoading")
                }
            }
            .padding(32)
        }
        .overlay(alignment: .topTrailing) { closeButton(on: .paper).padding(.trailing, 16).padding(.top, 8) }
        .environment(\.colorScheme, .light)
    }

    private func load() async {
        guard rewind == nil else { return }
        do {
            let summaries = try await model.entries(year: year)
            progress = 0.25
            let tagDates = (try? await model.tagDates())?.hashtags ?? []
            let ownName = model.me?.firstName
            let year = year
            let built = await Task.detached(priority: .userInitiated) {
                Rewind.build(year: year, summaries: summaries, ownName: ownName, tagDates: tagDates)
            }.value
            progress = 0.4
            guard built.entries.count >= RewindSeason.minimumEntries else {
                error = "There aren't enough entries in \(String(year)) for a Rewind yet."
                return
            }
            if JournalIntelligence.isEnabled(for: model.me) {
                if let saved = RewindStory.saved(for: built) {
                    story = saved
                } else {
                    isWriting = true
                    story = await JournalIntelligence.rewindStory(for: built) { progress = 0.4 + 0.6 * $0 }
                    guard !Task.isCancelled else { return }
                    story.save(for: built)
                }
            }
            progress = 1
            withAnimation(.easeOut(duration: 0.3)) { rewind = built }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Cards

    private enum Card: Hashable {
        case cover, showedUp, month, gap, people, places, soundtrack, hashtags, line, closing, photos
    }

    /// The cards this year has something for, in order.
    private func deck(_ rewind: Rewind) -> [Card] {
        var deck: [Card] = [.cover, .showedUp]
        if rewind.biggestMonth != nil { deck.append(.month) }
        if rewind.longestGap != nil { deck.append(.gap) }
        if !rewind.people.isEmpty { deck.append(.people) }
        if rewind.places.count >= 2 { deck.append(.places) }
        if !rewind.songs.isEmpty { deck.append(.soundtrack) }
        if !rewind.hashtags.isEmpty { deck.append(.hashtags) }
        if story.line != nil { deck.append(.line) }
        deck.append(.closing)
        if !rewind.photos.isEmpty { deck.append(.photos) }
        return deck
    }

    private func tone(for card: Card) -> Tone {
        switch card {
        case .cover: .marigold
        case .showedUp: .ink
        case .month: .olive
        case .gap: .sage
        case .people: .clay
        case .places: .sky
        case .soundtrack: .ink
        case .hashtags: .paper
        case .line: .olive
        case .closing: .marigold
        case .photos: .paper
        }
    }

    private func cards(for rewind: Rewind) -> some View {
        let deck = deck(rewind)
        let card = deck[min(index, deck.count - 1)]
        let tone = tone(for: card)
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                tone.background.ignoresSafeArea()
                content(card, rewind)
                    .foregroundStyle(tone.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .id(card)
                    .transition(.opacity)
            }
            .contentShape(.rect)
            // The story's taps: the left edge goes back, anywhere else goes on.
            .onTapGesture(coordinateSpace: .local) { point in
                move(point.x < geometry.size.width * 0.3 ? -1 : 1, in: deck)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 3) {
                    ForEach(deck.indices, id: \.self) { step in
                        Capsule()
                            .fill(tone.text.opacity(step <= index ? 1 : 0.25))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) { closeButton(on: tone).padding(.trailing, 14).padding(.top, 20) }
        }
        .animation(.easeOut(duration: 0.22), value: index)
        .environment(\.colorScheme, .light) // the cards bring their own colors
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next") { move(1, in: deck) }
        .accessibilityAction(named: "Previous") { move(-1, in: deck) }
    }

    private func move(_ by: Int, in deck: [Card]) {
        index = min(max(index + by, 0), deck.count - 1)
    }

    private func closeButton(on tone: Tone) -> some View {
        Button { dismiss() } label: {
            appIcon("slab-close")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(tone.text)
                .frame(width: 40, height: 40)
                .background(tone.text.opacity(0.12), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    @ViewBuilder
    private func content(_ card: Card, _ rewind: Rewind) -> some View {
        switch card {
        case .cover: cover(rewind)
        case .showedUp: showedUp(rewind)
        case .month: month(rewind)
        case .gap: gap(rewind)
        case .people: people(rewind)
        case .places: places(rewind)
        case .soundtrack: soundtrack(rewind)
        case .hashtags: hashtags(rewind)
        case .line: line
        case .closing: closing(rewind)
        case .photos: photos(rewind)
        }
    }

    // MARK: - Each card

    private func cover(_ rewind: Rewind) -> some View {
        let photos = rewind.photos
        let name = model.me?.firstName.map { "\($0)’s journal" } ?? "Your journal"
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("\(name), \(rewind.span)")
            Big("\(String(year)) Rewind", size: 84)
            Text(photos.isEmpty
                ? "\(entries(rewind.entries.count)). Here’s what you wrote down."
                : "\(entries(rewind.entries.count)) and \(photos.count == 1 ? "a photo" : "\(photos.count) photos"). Here’s what you wrote down.")
                .font(.system(.title3, design: .serif))
            Spacer(minLength: 12)
            // Three from across the year: its first, middle and last.
            PhotoSpread(entries: [photos.first, photos.count > 2 ? photos[photos.count / 2] : nil, photos.count > 1 ? photos.last : nil].compactMap { $0 })
            Spacer(minLength: 12)
            Text("Tap to go on. Tap the left edge to go back.")
                .font(.footnote)
                .opacity(0.7)
        }
    }

    private func showedUp(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("You showed up")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Big(rewind.entries.count.formatted(), size: 130)
                Text(rewind.entries.count == 1 ? "time" : "times").font(.system(.title, design: .serif, weight: .semibold))
            }
            Text("Every dot is a day you wrote something.")
                .font(.system(.body, design: .serif))
                .opacity(0.85)
            YearDots(year: year, days: rewind.days, through: model.today?.day ?? JournalDay(localDate: .now))
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 8) {
                fact("~\(rounded(rewind.wordCount))", "words, about \(rewind.averageWords.formatted()) an entry")
                if !rewind.photos.isEmpty {
                    fact(rewind.photos.count.formatted(), rewind.photos.count == 1 ? "entry came with a photo" : "entries came with photos")
                }
                if let day = rewind.busiestWeekday {
                    fact(String(day.name.prefix(3)), "your day, with \(entries(day.count))")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .opacity(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    private func month(_ rewind: Rewind) -> some View {
        let month = rewind.biggestMonth ?? (1, 0)
        let photos = rewind.entries(inMonth: month.month).filter { $0.imageUrl != nil }
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("Your biggest month")
            Big(Rewind.monthName(month.month), size: 110)
            Text([entries(month.count) + ".", story.monthCaption].compactMap { $0 }.joined(separator: " "))
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            PhotoSpread(entries: Array(photos.prefix(3)))
            Spacer(minLength: 0)
        }
    }

    private func gap(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Your longest silence")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Big((rewind.longestGap?.days ?? 0).formatted(), size: 130)
                Text("days").font(.system(.title, design: .serif, weight: .semibold))
            }
            if let gap = rewind.longestGap {
                Text("\(gap.from.formatted(.dateTime.month(.wide).day())) to \(gap.to.formatted(.dateTime.month(.wide).day())). Then you picked it back up.")
                    .font(.system(.title3, design: .serif))
            }
            Spacer(minLength: 0)
        }
    }

    private func people(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Who showed up most")
            ForEach(Array(rewind.people.prefix(3).enumerated()), id: \.element.id) { rank, person in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(rank + 1)")
                        .font(.custom("InstrumentSerif-Regular", size: 44))
                        .opacity(0.6)
                        .frame(width: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.custom("InstrumentSerif-Regular", size: 56))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text([entries(person.count), story.peopleCaptions[person.id]].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(.subheadline, design: .serif))
                            .opacity(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Counted by the entries that use their names.")
                .font(.footnote)
                .opacity(0.75)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private func places(_ rewind: Rewind) -> some View {
        let places = Array(rewind.places.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("You got around")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Big(rewind.places.count.formatted(), size: 130)
                Text("places").font(.system(.title, design: .serif, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(places) { place in
                    dated(place.firstDay.formatted(.dateTime.month(.abbreviated)), place.name)
                }
            }
            Text("The places your entries name.")
                .font(.footnote)
                .opacity(0.75)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private func dated(_ date: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(date.uppercased())
                .font(.caption.weight(.semibold))
                .opacity(0.7)
                .frame(width: 44, alignment: .leading)
            Text(text)
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func soundtrack(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Your \(String(year)) soundtrack")
            ForEach(Array(rewind.songs.prefix(4).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("“\(item.song.title ?? "A song")”")
                        .font(.custom("InstrumentSerif-Regular", size: 38))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text([item.song.artists.joined(separator: ", "), item.day.formatted(.dateTime.month(.wide).day())]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .opacity(0.85)
                    Link(destination: item.song.spotifyUrl) {
                        Label("Play on Spotify", icon: "slab-music")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.14), in: .capsule)
                    }
                    .padding(.top, 2)
                }
            }
            if rewind.songs.count > 4 {
                Text("And \(rewind.songs.count - 4) more in Journal › Playlist.")
                    .font(.footnote)
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    private func hashtags(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("What you tagged")
            if let top = rewind.hashtags.first {
                Big("#\(top.tag)", size: 84)
                Text("Your most used hashtag, on \(entries(top.count)).")
                    .font(.system(.title3, design: .serif))
            }
            FlowLayout(spacing: 8) {
                ForEach(rewind.hashtags.dropFirst().prefix(8)) { tag in
                    Text("#\(tag.tag) \(tag.count)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color("AccentColor").opacity(0.14), in: .capsule)
                }
            }
            if !rewind.milestones.isEmpty {
                Kicker("Along the way").padding(.top, 8)
                ForEach(rewind.milestones.prefix(4)) { milestone in
                    Text("#\(milestone.tag): \(milestone.years == 1 ? "1 year" : "\(milestone.years) years") in \(String(year))")
                        .font(.system(.title3, design: .serif))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var line: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Line of the year")
            Text("“\(story.line ?? "")”")
                .font(.custom("InstrumentSerif-Regular", size: 40))
                .lineSpacing(2)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: false)
            if let day = story.lineDay.flatMap(JournalDay.init) {
                Text("You, \(day.formatted(.dateTime.month(.wide).day()))")
                    .font(.system(.subheadline, design: .serif))
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
    }

    private func closing(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let words = story.sixWords {
                Kicker("\(String(year)), in a few words")
                Text(words)
                    .font(.custom("InstrumentSerif-Regular", size: 64))
                    .lineSpacing(0)
                    .minimumScaleFactor(0.5)
            } else {
                Kicker("That’s \(String(year))")
                Big(entries(rewind.entries.count), size: 84)
                Text("\(rewind.days.count == 1 ? "One day" : "\(rewind.days.count.formatted()) days") you’ll be able to look back on. Keep writing them down.")
                    .font(.system(.title3, design: .serif))
            }
            Spacer(minLength: 0)
            if rewind.photos.isEmpty {
                Button("Start Over") { index = 0 }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Tone.marigold.text)
            } else {
                Text("Tap for every photo.")
                    .font(.footnote)
                    .opacity(0.7)
            }
        }
    }

    private func photos(_ rewind: Rewind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Every photo from \(String(year))")
            Text("Tap one to open that day.")
                .font(.footnote)
                .opacity(0.7)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], spacing: 4) {
                    ForEach(rewind.photos.reversed()) { entry in
                        Button {
                            // The Journal opens it, once this has closed.
                            dismiss()
                            model.selectedTab = .journal
                            model.openEntryRequest = entry.id
                        } label: {
                            Color.black.opacity(0.08)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    AsyncImage(url: entry.thumbnail) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                }
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo from \(entry.day.long)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button("Start Over") { index = 0 }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color("AccentColor"))
        }
    }

    private func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count.formatted()) entries"
    }

    /// "4,000" for 4,137: a round number reads better after "~".
    private func rounded(_ words: Int) -> String {
        let step = words >= 10_000 ? 1_000 : words >= 1_000 ? 100 : 10
        return (Int((Double(words) / Double(step)).rounded()) * step).formatted()
    }
}

/// A card's colors: Dabble's paper, ink and olive, and a few accents beside them. The same in
/// Light and Dark Mode: the cards are their own little world.
private struct Tone {
    let background: Color
    let text: Color

    private static let inkColor = Color(red: 0x16 / 255, green: 0x17 / 255, blue: 0x14 / 255)
    private static let paperColor = Color(red: 0xF9 / 255, green: 0xF7 / 255, blue: 0xF3 / 255)

    static let paper = Tone(background: paperColor, text: inkColor)
    static let ink = Tone(background: inkColor, text: paperColor)
    static let olive = Tone(background: Color(red: 0x5C / 255, green: 0x66 / 255, blue: 0x54 / 255), text: paperColor)
    static let sage = Tone(background: Color(red: 0xD9 / 255, green: 0xDE / 255, blue: 0xCF / 255), text: inkColor)
    static let marigold = Tone(background: Color(red: 0xEC / 255, green: 0xB5 / 255, blue: 0x4A / 255), text: inkColor)
    static let clay = Tone(background: Color(red: 0xB8 / 255, green: 0x57 / 255, blue: 0x3A / 255), text: paperColor)
    static let sky = Tone(background: Color(red: 0xB4 / 255, green: 0xCB / 255, blue: 0xD8 / 255), text: inkColor)
}

/// The small line over a card's headline.
private struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A card's headline number or word, in the wordmark's Instrument Serif, as large as fits its line.
private struct Big: View {
    let text: String
    let size: CGFloat
    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.custom("InstrumentSerif-Regular", size: size))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .padding(.vertical, -size * 0.08) // the face's line is taller than its letters
    }
}

/// A few of the year's photos, set down like prints: white edges, a little askew.
private struct PhotoSpread: View {
    let entries: [Rewind.Entry]

    var body: some View {
        if !entries.isEmpty {
            HStack(spacing: -10) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Color.black.opacity(0.1)
                        .aspectRatio(0.82, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: entry.thumbnail) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        }
                        .clipped()
                        .padding(5)
                        .background(.white)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                        .rotationEffect(.degrees([-4.0, 2.5, -1.5][index % 3]))
                        .zIndex(index == 1 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 220)
            .accessibilityHidden(true)
        }
    }
}

/// The year as twelve rows of dots, a month each: filled for a day with an entry, faint for one
/// without, fainter still for days yet to come.
private struct YearDots: View {
    let year: Int
    let days: Set<String>
    let through: JournalDay

    var body: some View {
        GeometryReader { geometry in
            let label: CGFloat = 16
            let gap: CGFloat = 2.5
            let dot = max(3, (geometry.size.width - label - gap * 31) / 31)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(1...12, id: \.self) { month in
                    HStack(spacing: gap) {
                        Text(String(Rewind.monthName(month).prefix(1)))
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.6)
                            .frame(width: label, alignment: .leading)
                        ForEach(1...31, id: \.self) { day in
                            Circle()
                                .opacity(opacity(month, day))
                                .frame(width: dot, height: dot)
                        }
                    }
                }
            }
        }
        .aspectRatio(31.0 / 12.6, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Calendar of \(String(year)): \(days.count) days with an entry")
    }

    private func opacity(_ month: Int, _ day: Int) -> Double {
        let iso = String(format: "%04d-%02d-%02d", year, month, day)
        guard JournalDay(iso) != nil else { return 0 } // no such day (February 30)
        if days.contains(iso) { return 1 }
        return iso > through.iso ? 0.08 : 0.2
    }
}

/// Stats' way in, in the Rewind's season (PRO): the year's Rewind once it has enough entries,
/// and before that, how many more it takes.
struct RewindCard: View {
    let stats: JournalStats
    let today: JournalDay
    @Environment(AppModel.self) private var model
    /// The Rewind year's entries (this year's from the stats; last year's, in January, looked up).
    @State private var lastYearCount: Int?
    @State private var showing = false

    private var year: Int? { RewindSeason.year(on: today) }
    private var count: Int? {
        guard let year else { return nil }
        return String(year) == today.year ? stats.entriesThisYear : lastYearCount
    }

    var body: some View {
        if let year, model.me?.isPro == true {
            Group {
                if let count {
                    if count >= RewindSeason.minimumEntries { ready(year) } else { soon(year, needs: RewindSeason.minimumEntries - count) }
                }
            }
            .task(id: year) {
                guard String(year) != today.year, lastYearCount == nil else { return }
                lastYearCount = (try? await model.writingDays(year: year))?.count
            }
            .fullScreenCover(isPresented: $showing) { RewindView(year: year) }
        }
    }

    private func ready(_ year: Int) -> some View {
        Button { showing = true } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(year)) Rewind")
                        .font(.custom("InstrumentSerif-Regular", size: 40))
                    Text("Look back on the year you wrote down.")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                Spacer(minLength: 8)
                appIcon("slab-angle-right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("AccentColor"), in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(String(year)) Rewind")
        .accessibilityHint("Opens a look back on your year")
    }

    private func soon(_ year: Int, needs: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(String(year)) Rewind")
                .font(.custom("InstrumentSerif-Regular", size: 32))
            Text("Your Rewind will be ready with \(needs == 1 ? "1 more entry" : "\(needs) more entries").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Paper"), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
    }
}
