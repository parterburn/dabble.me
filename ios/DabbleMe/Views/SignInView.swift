import SwiftUI

/// Signed out: the real app's tabs, each showing a glimpse of what it holds, with sign-in and
/// sign-up front and center on Today. Everything shown here is made up; nothing is loaded.
struct SignInView: View {
    @State private var selected = "Today"
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selected) {
            Tab("Today", image: icon("slab-calendar", "Today"), value: "Today") { WelcomeView().tabBarClearance() }
            Tab("Journal", image: icon("slab-book", "Journal"), value: "Journal") {
                LockedGlimpse(icon: "slab-book",
                              title: "The private timeline of your life",
                              message: "Every entry and photo, in order and just for you. Jump back a week or ten years.") {
                    SampleJournal()
                }
                .tabBarClearance()
            }
            Tab("Search", image: icon("slab-search", "Search"), value: "Search") {
                LockedGlimpse(icon: "slab-search",
                              title: "Find any moment",
                              message: "Search every word you've ever written, or tap one of your #hashtags.") {
                    SampleHashtags()
                }
                .tabBarClearance()
            }
            Tab("Settings", image: icon("slab-gear", "Settings"), value: "Settings") { GuestSettings().tabBarClearance() }
        }
        .opensDabbleLinksInApp()
        // Sign in and sign up are the app's own forms (passkeys go to dabble.me from there).
        .sheet(item: $model.authForm) { mode in
            AuthFormView(mode: mode)
                .opensDabbleLinksInApp()
        }
    }

    /// The selected tab shows the filled version of its icon.
    private func icon(_ name: String, _ tab: String) -> String {
        selected == tab ? name + "-full" : name
    }
}

/// The "Dabble me." wordmark from dabble.me: Instrument Serif with an olive period and, like the
/// site's header, a blinking grey cursor after it. `typesOut` types it letter by letter when it
/// appears (the splash and the welcome screen); the space it takes never changes, so nothing
/// shifts as it types.
struct Wordmark: View {
    var size: CGFloat = 64
    var typesOut = false
    var showsCursor = false
    var pace = Pace.quick
    /// How many letters are typed so far (nil: all of them, nothing being typed).
    @State private var typed: Int?
    @State private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One that types itself out starts with nothing written, from its first frame (not written
    /// out in full for a moment first).
    init(size: CGFloat = 64, typesOut: Bool = false, showsCursor: Bool = false, pace: Pace = .quick) {
        self.size = size
        self.typesOut = typesOut
        self.showsCursor = showsCursor
        self.pace = pace
        _typed = State(initialValue: typesOut ? 0 : nil)
    }

    nonisolated static let letters = Array("Dabble me.")

    /// How fast it types. Quick (about 0.6 seconds in all) where something waits on it, as the
    /// app does on the splash; unhurried (about 1.1) where nothing does, as on Today.
    enum Pace {
        case quick, unhurried

        /// The pause before the first letter, in milliseconds.
        var leadIn: Int { self == .quick ? 100 : 200 }

        /// After each letter: a little unevenly, like someone typing, with a beat before the period.
        var pauses: [Int] {
            (1...Wordmark.letters.count).map { index in
                let beforePeriod = index == Wordmark.letters.count - 1
                switch self {
                case .quick: return beforePeriod ? 110 : 32 + (index * 37) % 28
                case .unhurried: return beforePeriod ? 180 : 55 + (index * 37) % 45
                }
            }
        }
    }

    /// How long typing it out takes, in milliseconds.
    static func typingDuration(_ pace: Pace = .quick) -> Int { pace.leadIn + pace.pauses.reduce(0, +) }

    var body: some View {
        line(Self.letters.count)
            .hidden()
            .overlay(alignment: .leading) { line(reduceMotion ? Self.letters.count : typed ?? Self.letters.count) }
            .accessibilityElement()
            .accessibilityLabel("Dabble Me")
            .task {
                // Once: not again each time it comes back into view (scrolled to, a tab returned to).
                guard typesOut, !reduceMotion, typed == 0 else { return }
                try? await Task.sleep(for: .milliseconds(pace.leadIn))
                for (index, pause) in pace.pauses.enumerated() {
                    typed = index + 1
                    try? await Task.sleep(for: .milliseconds(pause))
                }
                typed = nil
            }
            .task(id: showsCursor) {
                // The site's blink: on and off every 0.65 seconds.
                guard showsCursor, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(650))
                    cursorOn.toggle()
                }
            }
    }

    private func line(_ count: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.12) {
            text(count)
                .kerning(-size / 150)
            if showsCursor {
                Text("|")
                    .foregroundStyle(.secondary)
                    .opacity(cursorOn ? 1 : 0)
            }
        }
        .font(.custom("InstrumentSerif-Regular", size: size))
    }

    private func text(_ count: Int) -> Text {
        let shown = String(Self.letters.prefix(count))
        guard shown.hasSuffix(".") else { return Text(shown) }
        return Text(shown.dropLast()) + Text(".").foregroundStyle(.tint)
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Wordmark(size: 72, typesOut: true, showsCursor: true)
                    Text("Your life, written down\nand remembered.")
                        .font(.custom("InstrumentSerif-Regular", size: 28))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                MemoryDeck()
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 12) {
                    Button {
                        model.authForm = .signUp
                    } label: {
                        Text("Start Your Journal")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .filledButtonStyle()
                    .controlSize(.large)

                    Button {
                        model.authForm = .signIn
                    } label: {
                        Text("I Already Have an Account")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if let notice = model.signInNotice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if let error = model.signInError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.deleteRed)
                            .multilineTextAlignment(.center)
                    }

                    Text("Free to start. No ads, no tracking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                #if DEBUG
                ServerPicker()
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color("Paper").ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { appeared = true }
        }
    }
}

/// A small stack of made-up memories that deals itself in and gently cycles, like flipping back
/// through old entries: the feeling of On This Day, before you have any. They show off what an
/// entry can hold: a photo, #hashtags, and a dated hashtag's age (#anniversary, as the entry pill shows it).
/// The photos are bundled CC0 samples (Flickr: "World's cutest snowman" by Lottie's pets & stuff,
/// "Bruges" by Daquella manera, "White coffee on the table" by freestocks.org), not anyone's journal.
private struct MemoryDeck: View {
    private struct Memory {
        let caption: String
        let text: String
        var photo: String? = nil
        /// A dated hashtag and its age on the entry's day, as the server words it.
        var datedTag: (tag: String, age: String)? = nil
    }

    private static let memories: [Memory] = [
        Memory(caption: "1 year ago", text: "Bruges for our #anniversary! Wandered the canals all afternoon and ate too many waffles.",
               photo: "SampleBruges", datedTag: ("anniversary", "9 years, 2 days")),
        Memory(caption: "3 years ago", text: "First snow of the year. Built a lopsided snowman, then cocoa by the window. #winter",
               photo: "SampleSnowman"),
        Memory(caption: "5 years ago", text: "Moved into the new apartment. No curtains yet, pizza on the floor. Already feels like #home."),
        Memory(caption: "Yesterday", text: "Made pour-over and read on the porch until noon. Grateful for quiet mornings. #gratitude",
               photo: "SampleCoffee"),
    ]

    @State private var front = 0
    @State private var dealt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The three memories showing, back to front: identified by the memory, so on each flip the
    /// cards behind slide forward as themselves. (Keyed by depth instead, every card cross-faded
    /// into the next one at once, and the back cards' text showed through the front card.)
    private var showing: [Int] {
        (0..<3).reversed().map { (front + $0) % Self.memories.count }
    }

    var body: some View {
        ZStack {
            ForEach(showing, id: \.self) { index in
                let position = (index - front + Self.memories.count) % Self.memories.count // 0 is the front
                card(Self.memories[index], isFront: position == 0)
                    .rotationEffect(.degrees(dealt ? Double(position) * -3.5 : 0))
                    .offset(y: dealt ? CGFloat(position) * -10 : 40)
                    .scaleEffect(position == 0 ? 1 : 0.96 - CGFloat(position - 1) * 0.02)
                    .zIndex(Double(3 - position))
                    // The front card slides away whole (no fade, so the card under it never shows
                    // through); the new one fades in at the back.
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading)))
            }
        }
        .frame(height: 216)
        .padding(.top, 8)
        .accessibilityElement()
        .accessibilityLabel("Examples of past entries resurfacing, like On This Day, with photos and hashtags")
        .task {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.3).delay(0.3)) { dealt = true }
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { front = (front + 1) % Self.memories.count }
            }
        }
    }

    private func card(_ memory: Memory, isFront: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(memory.caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Self.withHashtags(memory.text)
                    .font(.system(.body, design: .serif))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let dated = memory.datedTag {
                    HashtagPill(tag: dated.tag, age: dated.age)
                }
                Spacer(minLength: 0)
            }
            if let photo = memory.photo {
                Image(photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 10))
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: 340, minHeight: 176, maxHeight: 176, alignment: .topLeading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(isFront ? 0.08 : 0.03), radius: isFront ? 12 : 4, y: isFront ? 6 : 2)
    }

    /// The entry's words with its #hashtags in the tint, as the timeline shows them.
    private static func withHashtags(_ text: String) -> Text {
        var attributed = AttributedString(text)
        let regex = try! NSRegularExpression(pattern: "(?<![\\w&/#])#([0-9]*[A-Za-z_][A-Za-z0-9_]*)")
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: attributed) else { continue }
            attributed[range].foregroundColor = Color("AccentColor")
        }
        return Text(attributed)
    }
}

/// A tab's content, dimmed behind a card that says what signing in unlocks: solid olive, so it
/// reads as the thing to tap rather than one more grey panel. Text and icon take OnAccent (white
/// on olive; dark green on the light sage olive of dark mode); the button is Paper with olive
/// text, the reverse of the app's usual filled button.
private struct LockedGlimpse<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let content: Content
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            content
                .redacted(reason: .placeholder)
                .blur(radius: 1.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                appIcon(icon)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.custom("InstrumentSerif-Regular", size: 30))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .opacity(0.85)
                    .multilineTextAlignment(.center)
                Button {
                    model.authForm = .signUp
                } label: {
                    Text("Start Your Journal")
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Paper"))
                .padding(.top, 2)
                Button("Sign In") { model.authForm = .signIn }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
            }
            .foregroundStyle(Color("OnAccent"))
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color("AccentColor"), in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding()
        }
        .background(Color("Paper").ignoresSafeArea())
    }
}

private struct SampleJournal: View {
    private let rows = [
        ("SAT", "7", "Finally made it to Yosemite. We started the Mist Trail before sunrise."),
        ("FRI", "6", "Slow Saturday. Made pour-over and read on the porch until noon."),
        ("WED", "4", "Big presentation went well. It felt like a conversation, not a performance."),
        ("TUE", "3", "The dog has discovered the heated blanket and will not be leaving it."),
        ("SUN", "1", "Ran 5 miles without stopping for the first time since the injury."),
        ("THU", "29", "Rainy day. Tea, soup, and the last hundred pages of a good book."),
    ]

    var body: some View {
        List {
            Section("November") {
                ForEach(rows, id: \.2) { row in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Text(row.0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(row.1).font(.title2.weight(.semibold))
                        }
                        .frame(width: 42)
                        Text(row.2).font(.system(.body, design: .serif)).lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct SampleHashtags: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Hashtags This Year").font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(["#hiking", "#family", "#gratitude", "#travel", "#reading", "#work", "#cooking", "#running"], id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: tag.count > 7 ? 15 : 22, design: .serif))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
            }
            Spacer()
        }
        .padding()
        .padding(.top, 60)
    }
}

private struct GuestSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { model.authForm = .signUp } label: { Label("Start Your Journal", icon: "slab-plus") }
                    Button { model.authForm = .signIn } label: { Label("Sign In", icon: "slab-arrow-right-to-bracket") }
                }
                Section {
                    Link(destination: AppConfig.webURL("support")) { ExternalLinkLabel("Help & Support", icon: "slab-circle-question") }
                    Link(destination: AppConfig.webURL("privacy")) { ExternalLinkLabel("Privacy Policy", icon: "slab-hand") }
                    Link(destination: AppConfig.webURL("terms")) { ExternalLinkLabel("Terms", icon: "slab-anchor") }
                }
                #if DEBUG
                Section("Development") { ServerPicker() }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
        }
    }
}
