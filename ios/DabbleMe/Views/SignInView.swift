import SwiftUI

/// Signed out: the real app's tabs, each showing a glimpse of what it holds, with sign-in and
/// sign-up front and center on Today. Everything shown here is made up; nothing is loaded.
struct SignInView: View {
    @State private var selected = "Today"

    var body: some View {
        TabView(selection: $selected) {
            Tab("Today", image: icon("slab-calendar", "Today"), value: "Today") { WelcomeView().tabBarClearance() }
            Tab("Journal", image: icon("slab-book", "Journal"), value: "Journal") {
                LockedGlimpse(title: "Your whole journal, by month",
                              message: "Every entry you've written, with photos, Stats and a timeline to jump years back.") {
                    SampleJournal()
                }
                .tabBarClearance()
            }
            Tab("Search", image: icon("slab-search", "Search"), value: "Search") {
                LockedGlimpse(title: "Find any moment",
                              message: "Search every word you've ever written, or tap one of your #hashtags.") {
                    SampleHashtags()
                }
                .tabBarClearance()
            }
            Tab("Settings", image: icon("slab-gear", "Settings"), value: "Settings") { GuestSettings().tabBarClearance() }
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
    @State private var typed: Int?
    @State private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let letters = Array("Dabble me.")

    /// A pause, then a little unevenly, like someone typing, with a beat before the period.
    private static let pauses: [Int] = (1...letters.count).map { index in
        index == letters.count - 1 ? 180 : 55 + (index * 37) % 45
    }
    /// How long typing it out takes, in milliseconds.
    static let typingDuration = 200 + pauses.reduce(0, +)

    var body: some View {
        line(Self.letters.count)
            .hidden()
            .overlay(alignment: .leading) { line(typed ?? Self.letters.count) }
            .accessibilityElement()
            .accessibilityLabel("Dabble Me")
            .onAppear { if typesOut, !reduceMotion, typed == nil { typed = 0 } }
            .task {
                guard typesOut, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(200))
                for (index, pause) in Self.pauses.enumerated() {
                    typed = index + 1
                    try? await Task.sleep(for: .milliseconds(pause))
                }
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
                        Task { await model.signIn(createAccount: true) }
                    } label: {
                        Text("Start Your Journal")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        Task { await model.signIn() }
                    } label: {
                        Group {
                            if model.isSigningIn {
                                ProgressView()
                            } else {
                                Text("I Already Have an Account")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if let error = model.signInError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text("Free to start. No ads, no tracking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .disabled(model.isSigningIn)
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
/// through old entries: the feeling of On This Day, before you have any.
private struct MemoryDeck: View {
    private static let memories: [(caption: String, text: String)] = [
        ("1 year ago", "Bruges! Wandered the canals all afternoon and ate an unreasonable number of waffles."),
        ("3 years ago", "First snow of the year. Built a lopsided snowman and drank cocoa by the window."),
        ("5 years ago", "Moved into the new apartment. No curtains yet, pizza on the floor. Already feels like home."),
        ("Yesterday", "Made pour-over and read on the porch until noon. Grateful for quiet mornings."),
    ]

    @State private var front = 0
    @State private var dealt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { depth in
                let index = (front + 2 - depth) % Self.memories.count
                let isFront = depth == 2
                card(Self.memories[index], isFront: isFront)
                    .rotationEffect(.degrees(dealt ? Double(depth - 2) * 3.5 : 0))
                    .offset(y: dealt ? CGFloat(2 - depth) * -10 : 40)
                    .scaleEffect(isFront ? 1 : 0.96 - CGFloat(1 - depth) * 0.02)
                    .zIndex(Double(depth))
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .frame(height: 190)
        .padding(.top, 8)
        .accessibilityElement()
        .accessibilityLabel("Examples of past entries resurfacing, like On This Day")
        .task {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.3).delay(0.3)) { dealt = true }
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { front = (front + 1) % Self.memories.count }
            }
        }
    }

    private func card(_ memory: (caption: String, text: String), isFront: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(memory.caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Text(memory.text)
                .font(.system(.body, design: .serif))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: 340, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(isFront ? 0.08 : 0.03), radius: isFront ? 12 : 4, y: isFront ? 6 : 2)
    }
}

/// A tab's content, dimmed behind a card that says what signing in unlocks.
private struct LockedGlimpse<Content: View>: View {
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
                appIcon("slab-lock")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.custom("InstrumentSerif-Regular", size: 30))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Start Your Journal") { Task { await model.signIn(createAccount: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Sign In") { Task { await model.signIn() } }
                    .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .padding()
            .disabled(model.isSigningIn)
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
                    Button { Task { await model.signIn(createAccount: true) } } label: { Label("Start Your Journal", icon: "slab-plus") }
                    Button { Task { await model.signIn() } } label: { Label("Sign In", icon: "slab-arrow-right-to-bracket") }
                }
                .disabled(model.isSigningIn)
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
