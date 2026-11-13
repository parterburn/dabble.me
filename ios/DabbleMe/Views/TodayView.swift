import SwiftUI

/// Today: write today's entry, and look back at this date in earlier years. Entries here are the
/// Journal's rows (tap to expand, again to open; swipe right for Actions, left to Open), and each
/// memory's date sticks at the top while you read it.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var composing = false
    @State private var showingProInfo = false
    @AppStorage(ShakeSetting.storageKey) private var shakeForRandomEntry = true
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
                    // The header (the nav bar is hidden here): the wordmark, small, with how many
                    // entries the journal holds ("1,204 entries") beside it.
                    HStack(alignment: .center) {
                        Wordmark(size: 28)
                        Spacer(minLength: 8)
                        // Nothing to count yet: no "0 entries".
                        if let count = model.me?.entryCount, count > 0 {
                            entryCountButton(count)
                        }
                    }
                    .plainRow()
                    // Today's date titles the day's section. No year: it's always today.
                    // Once today's written, a pencil at the far right edits it (PRO).
                    HStack(spacing: 8) {
                        SectionTitle(today.day?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? today.date,
                                     icon: "slab-calendar")
                            .accessibilityLabel(today.day?.long ?? today.date)
                        Spacer(minLength: 8)
                        if let entry = today.entry, model.me?.canEdit == true {
                            editTodayButton(entry)
                        }
                    }
                        .plainRow()
                        // Close above the prompt card (which has its own space); a little more
                        // above today's entry, whose card starts at the row's edge.
                        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: today.entry == nil ? 0 : 8, trailing: 20))
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
            .listSectionSpacing(0) // a memory's date sits right under its section's title
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
            // From the widget's "Add to today": today's entry, open for editing, once Today has
            // loaded it (the app may be starting up). Nothing written after all: write it.
            .onChange(of: "\(model.editTodayRequest)|\(model.today?.date ?? "")|\(model.today?.entry?.id ?? 0)", initial: true) {
                guard model.editTodayRequest, let today = model.today else { return }
                model.editTodayRequest = false
                if let entry = today.entry {
                    if model.me?.canEdit == true { Task { await actions.edit(entry.id, model: model) } }
                } else {
                    composing = true
                }
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
                        .accessibilityIdentifier("TodayPrompt")
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
        let curated = await model.curatedPrompts()
        do {
            let text = try await JournalIntelligence.startingPrompt(curated: curated, recent: recent, today: day)
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

    /// The pencil beside today's date, a round button like the Journal's New Entry: straight into
    /// editing today's entry, to add to the day (or to its edit page on dabble.me, for one the app
    /// can't edit).
    private func editTodayButton(_ entry: EntryDetail) -> some View {
        Button {
            Task { await actions.edit(entry.id, model: model) }
        } label: {
            appIcon("slab-edit")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .modifier(ToolbarCircle())
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit Today's Entry")
    }

    /// In Rewind's season, for someone it's ready for (PRO, with enough entries this year), the
    /// count wears Rewind's icon: Stats opens with the year's Rewind at its top.
    private var rewindIsOn: Bool {
        guard model.me?.isPro == true, let today = model.today, let day = today.day, let year = RewindSeason.year(on: day) else { return false }
        return String(year) != day.year || (today.entriesThisYear ?? 0) >= RewindSeason.minimumEntries
    }

    /// "▮ 1,204 entries": every entry in the journal, behind the Stats icon. Tapping it opens Stats.
    private func entryCountButton(_ count: Int) -> some View {
        Button {
            model.selectedTab = .journal
            model.statsRequest += 1
        } label: {
            // The Stats icon says where it goes.
            HStack(spacing: 5) {
                appIcon(rewindIsOn ? "slab-backward" : "slab-chart-bar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: rewindIsOn ? 17 : 15, height: rewindIsOn ? 17 : 15)
                Text("\(count.formatted()) \(count == 1 ? "entry" : "entries")")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .lineLimit(1)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(count == 1 ? "1 entry" : "\(count) entries")
        .accessibilityHint("Shows your stats")
    }

    /// On This Day when there's something from this exact date in past years; otherwise a Rewind
    /// (any past entry, as in the daily email; the API calls it `throwback`), or, with nothing to look back on yet, a nudge to write.
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
        SectionTitle("Rewind", icon: "slab-backward")
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

    /// "2 years and 3 months ago • August 2024": on one line, and the day itself is on the row
    /// under it (SAT 10).
    private static func throwbackTitle(_ entry: EntrySummary, today: TodaySummary) -> String {
        guard let day = entry.day else { return entry.date }
        guard let now = today.day else { return day.monthTitle }
        return "\(day.relative(to: now)) • \(day.monthTitle)"
    }

    @ViewBuilder
    private func memoriesSection(_ today: TodaySummary) -> some View {
        // A little more under it than a Rewind's: several days can follow, each with its own date.
        SectionTitle("On This Day", icon: "slab-backward")
            .sectionTitleRow(bottom: 10)
        if !today.onThisDayAvailable {
            Text("See what you wrote on this date in past years with Dabble Me PRO.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .plainRow()
            // Meanwhile, a look back that's free: the random memory sheet (also a shake away),
            // once there's an entry from a day before today to come up in it.
            if (model.me?.entryCount ?? 0) - (today.entry == nil ? 0 : 1) >= 1 {
                // Olive words, not a button's shape: it says what a shake does (a tap does it too),
                // or, for someone who's switched the shake off, what pulling past Today's end does.
                Button {
                    model.showsRandomEntry = true
                } label: {
                    // The dice close to its words (a Label leaves more room between them).
                    HStack(spacing: 8) {
                        appIcon("slab-dice")
                        Text(shakeForRandomEntry ? "Shake for a Random Entry" : "Keep scrolling for a Random Memory")
                    }
                        .fontWeight(.medium)
                        .foregroundStyle(.tint)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .plainRow()
            }
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

    /// "1 year ago • November 2025".
    private static func memoryTitle(_ memory: EntrySummary) -> String {
        let month = memory.day?.monthTitle ?? memory.date
        guard let years = memory.yearsAgo else { return month }
        return "\(years == 1 ? "1 year" : "\(years) years") ago • \(month)"
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
    func sectionTitleRow(bottom: CGFloat = 2) -> some View {
        plainRow()
            .listRowInsets(EdgeInsets(top: 23, leading: 20, bottom: bottom, trailing: 20))
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

/// The circle a navigation bar gives its buttons (glass, where there is glass), for a button of
/// the same standing that isn't in a bar.
private struct ToolbarCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: .circle)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        }
    }
}
