import SwiftUI

/// Today: write today's entry, and look back at this date in earlier years. Entries here are the
/// Journal's rows (tap to expand, again to open; swipe right for Actions, left to Open), and each
/// memory's date sticks at the top while you read it.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var composing = false
    @State private var showingProInfo = false
    /// A prompt Apple Intelligence wrote from recent entries (PRO, on device), for this day only.
    /// With Apple Intelligence on (PRO), Today's prompt is written from recent entries on the device,
    /// once a day (kept for that day), instead of the general daily prompt.
    @AppStorage("ai.prompt.day") private var aiPromptDay = ""
    @AppStorage("ai.prompt.text") private var aiPromptText = ""
    @State private var isWritingPrompt = false
    @State private var promptError: String?
    @State private var expanded: Set<Int> = []
    @State private var actions = EntryActions()
    /// How far past the bottom Today is pulled: far enough, and letting go opens a random memory.
    @State private var bottomPull: CGFloat = 0
    private let randomMemoryPull: CGFloat = 90

    var body: some View {
        NavigationStack(path: $path) {
            // A list (not a plain scroll view) so On This Day rows swipe like the Journal's.
            List {
                if let today = model.today {
                    // The date is the page title (the nav bar is hidden here), with the writing
                    // streak beside it. No year: it's always today. One line, shrinking a little
                    // for long dates.
                    HStack(alignment: .firstTextBaseline) {
                        Text(today.day?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? today.date)
                            .font(.system(.title, design: .serif, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityLabel(today.day?.long ?? today.date)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        streakButton(today.currentStreak ?? 0)
                    }
                    .plainRow()
                    todaySection(today)
                    onThisDaySection(today)
                } else if let error = model.timelineError {
                    ContentUnavailableView("Couldn't load today", systemImage: "wifi.exclamationmark", description: Text(error))
                        .plainRow()
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                        .plainRow()
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1) // rows as tall as their content (the section titles)
            // Pull to reset: collapses expanded entries and reloads today. On the list itself,
            // inside the sheets and entry pages below, so they don't inherit a pull-to-refresh.
            .refreshable {
                withAnimation(.snappy(duration: 0.25)) { expanded = [] }
                await model.loadToday()
            }
            .timelinePinsDates()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .entryActionSheets(actions)
            .navigationTitle("Today") // back-button label on entries opened from here
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
            // An easter egg: keep pulling up past the bottom and let go for a random memory, in the
            // same sheet as a shake. Only on letting go of a drag (a flick that bounces doesn't count).
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Past the furthest it can scroll. Content shorter than the screen (still loading)
                // can't scroll at all, so it isn't "past the bottom" until it's actually pulled.
                let visible = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
                let maxOffset = max(geometry.contentSize.height - visible, 0) - geometry.contentInsets.top
                return geometry.contentOffset.y - maxOffset
            } action: { _, overscroll in
                bottomPull = max(0, overscroll)
            }
            .onScrollPhaseChange { old, new in
                guard old == .interacting, new != .interacting, bottomPull >= randomMemoryPull,
                      model.hasLoaded, !model.months.isEmpty, !model.showsRandomEntry else { return }
                model.showsRandomEntry = true
            }
            .overlay(alignment: .bottom) {
                if bottomPull > 12 {
                    let armed = bottomPull >= randomMemoryPull
                    Text(armed ? "Let go for a random memory" : "Keep pulling for a random memory")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .opacity(min(1, (bottomPull - 12) / 40))
                        .padding(.bottom, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: bottomPull >= randomMemoryPull) { _, armed in armed }
            .onChange(of: model.composeRequest, initial: true) { _, requested in
                guard requested else { return }
                model.composeRequest = false
                composing = true
            }
            .sheet(isPresented: $composing) { ComposeView(mode: .new) }
            .sheet(isPresented: $showingProInfo) { ProInfoView(feature: .writing) }
            .alert("Couldn't write a prompt", isPresented: .present($promptError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(promptError ?? "")
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private func todaySection(_ today: TodaySummary) -> some View {
        if let entry = today.entry {
            SectionTitle("Today's Entry", icon: "slab-calendar")
                .padding(.top, 6)
                .plainRow()
            // On the prompt box's Paper card, so today stands apart from On This Day. The card is
            // the row's background, so the entry keeps its swipes.
            row(entry.summary)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 32, bottom: 24, trailing: 32))
                .listRowBackground(TodayCard())
        } else {
            VStack(alignment: .leading, spacing: 14) {
                let usesAI = JournalIntelligence.isEnabled(for: model.me)
                let personal = usesAI && aiPromptDay == today.date && !aiPromptText.isEmpty ? aiPromptText : nil
                if usesAI, personal == nil, isWritingPrompt {
                    // Writing today's prompt; the general one would just flash and change.
                    Text("A prompt for you")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tint)
                    Text("What stood out to you about today, and why?")
                        .font(.system(.title2, design: .serif))
                        .redacted(reason: .placeholder)
                        .accessibilityLabel("Writing a prompt for you")
                } else if let prompt = personal ?? today.prompt {
                    HStack {
                        Text(personal != nil ? "A prompt for you" : "Today's prompt")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.tint)
                        Spacer()
                        if usesAI, personal != nil {
                            // Another prompt: an icon in the card's top-right corner.
                            Button {
                                Task { await writePrompt(for: today) }
                            } label: {
                                if isWritingPrompt {
                                    ProgressView().controlSize(.small)
                                } else {
                                    appIcon("slab-arrows-rotate")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 32, height: 32) // the tap target stays comfortable
                            .contentShape(.rect)
                            .padding(.vertical, -8) // keep the label row's height
                            .disabled(isWritingPrompt)
                            .accessibilityLabel("Another Prompt")
                        }
                    }
                    Text(prompt)
                        .font(.system(.title2, design: .serif))
                        .contentTransition(.opacity)
                } else {
                    Text("How was your day?")
                        .font(.system(.title2, design: .serif))
                }
                if model.me?.canWrite == false {
                    Text("Reply to today's Dabble Me email and it'll show up here as your entry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        composing = true
                    } label: {
                        Text("Write Today's Entry")
                            .fontWeight(.medium) // the main call to action
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .background(Color("Paper"), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            .padding(.vertical, 8)
            .plainRow()
            .task(id: "\(today.date)|\(JournalIntelligence.isEnabled(for: model.me))") {
                guard JournalIntelligence.isEnabled(for: model.me), aiPromptDay != today.date else { return }
                await writePrompt(for: today, quietly: true)
            }
        }
    }

    /// `quietly`: the automatic one when Today opens; if it fails, the general prompt stays.
    private func writePrompt(for today: TodaySummary, quietly: Bool = false) async {
        guard !isWritingPrompt else { return }
        isWritingPrompt = true
        defer { isWritingPrompt = false }
        let day = today.day ?? JournalDay(localDate: .now)
        let recent = JournalIntelligence.dated((try? await model.recentEntries()) ?? [], today: day)
        do {
            let text = try await JournalIntelligence.reflectionPrompt(from: recent, today: day)
            withAnimation {
                aiPromptDay = today.date
                aiPromptText = text
            }
            WidgetSync.update(from: model)
        } catch is CancellationError {
        } catch {
            if !quietly { promptError = error.localizedDescription }
        }
    }

    // MARK: - On This Day

    /// "🔥 4": days in a row with an entry. Tapping it opens Stats.
    private func streakButton(_ streak: Int) -> some View {
        Button {
            model.selectedTab = .journal
            model.statsRequest += 1
        } label: {
            HStack(spacing: 4) {
                appIcon("slab-fire")
                Text(streak.formatted())
                    .monospacedDigit()
            }
            .font(.headline)
            .foregroundStyle(streak > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(streak == 1 ? "1 day streak" : "\(streak) day streak")
        .accessibilityHint("Shows your stats")
    }

    /// On This Day when there's something from this date in past years; otherwise a Throwback
    /// (any past entry, as in the daily email), or, with nothing to look back on yet, a nudge to write.
    /// Free accounts see On This Day as a PRO feature instead.
    @ViewBuilder
    private func onThisDaySection(_ today: TodaySummary) -> some View {
        if !today.onThisDayAvailable {
            memoriesSection(today)
        } else if today.onThisDay.isEmpty {
            throwbackSection(today.throwback, today: today)
        } else {
            memoriesSection(today)
        }
    }

    @ViewBuilder
    private func throwbackSection(_ throwback: EntrySummary?, today: TodaySummary) -> some View {
        SectionTitle("Throwback", icon: "slab-backward")
            .sectionTitleRow()
        if let throwback {
            Section {
                row(throwback)
                    .timelineRowLayout()
            } header: {
                MonthHeader(title: Self.throwbackTitle(throwback, today: today), isDay: true)
            }
        } else {
            Text("This is where your past entries come back to you. Write a little today, and one day you'll find it waiting here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .plainRow()
        }
    }

    /// "31 days ago · Wednesday, May 20, 2026".
    private static func throwbackTitle(_ entry: EntrySummary, today: TodaySummary) -> String {
        let date = entry.day?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? entry.date
        guard let day = entry.day, let now = today.day else { return date }
        return "\(day.relative(to: now)) · \(date)"
    }

    @ViewBuilder
    private func memoriesSection(_ today: TodaySummary) -> some View {
        SectionTitle("On This Day", icon: "slab-backward")
            .sectionTitleRow()
        if !today.onThisDayAvailable {
            Text("See what you wrote on this date in past years with Dabble Me PRO.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .plainRow()
            // Meanwhile, a look back that's free: the random memory sheet (also a shake away).
            Button {
                model.showsRandomEntry = true
            } label: {
                Label("Try a Random Memory", icon: "slab-dice")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .plainRow()
        }
        // One section per memory, so its date sticks at the top while you scroll through it.
        ForEach(today.onThisDay) { memory in
            Section {
                row(memory)
                    .timelineRowLayout()
            } header: {
                MonthHeader(title: Self.memoryTitle(memory), isDay: true)
            }
        }
    }

    /// "1 year ago · Saturday, November 8, 2025".
    private static func memoryTitle(_ memory: EntrySummary) -> String {
        let date = memory.day?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? memory.date
        guard let years = memory.yearsAgo else { return date }
        return "\(years == 1 ? "1 year" : "\(years) years") ago · \(date)"
    }

    /// The Journal's row: tap to expand a long one (or open it); swipe right for Actions, left to Open.
    private func row(_ entry: EntrySummary) -> some View {
        TimelineEntryRow(entry: entry, isExpanded: expanded.contains(entry.id), actions: actions,
                         onExpand: { withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) } },
                         onOpen: { path.append(EntryRoute(id: entry.id)) })
            .entryRowMenu(entry, actions: actions) { path.append(EntryRoute(id: entry.id)) }
    }
}

private extension View {
    /// On This Day's and Throwback's title: room above it, little below, so the first entry's
    /// date follows close behind.
    func sectionTitleRow() -> some View {
        plainRow()
            .listRowInsets(EdgeInsets(top: 23, leading: 20, bottom: 2, trailing: 20))
    }

    /// A list row that's just page content: no separator, no row background.
    func plainRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct SectionTitle: View {
    let title: String
    var icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                // Light grey: a label's icon, not a button (Today's other icons are tappable).
                appIcon(icon)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The Paper card behind Today's Entry, the same as the prompt box's.
private struct TodayCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color("Paper"))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            // Inset like the prompt box, which sits within the list's margins.
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)
    }
}
