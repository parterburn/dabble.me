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

    var body: some View {
        NavigationStack(path: $path) {
            // A list (not a plain scroll view) so On This Day rows swipe like the Journal's.
            List {
                if let today = model.today {
                    // The date is the page title (the nav bar is hidden here).
                    // No year: it's always today. One line, shrinking a little for long dates.
                    Text(today.day?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? today.date)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(today.day?.long ?? today.date)
                        .accessibilityAddTraits(.isHeader)
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
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .entryActionSheets(actions)
            .navigationTitle("Today") // back-button label on entries opened from here
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
            .refreshable { await model.loadToday() }
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
                .plainRow()
            row(entry.summary, showsDate: false)
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

    @ViewBuilder
    private func onThisDaySection(_ today: TodaySummary) -> some View {
        SectionTitle("On This Day", icon: "slab-backward")
            .padding(.top, 12)
            .plainRow()
        if !today.onThisDayAvailable {
            Text("See what you wrote on this date in past years with Dabble Me PRO.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .plainRow()
        } else if today.onThisDay.isEmpty {
            Text("Nothing from this date in earlier years yet. Write today, and next year it'll be waiting for you here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .plainRow()
        } else {
            // One section per memory, so its date sticks at the top while you scroll through it.
            ForEach(today.onThisDay) { memory in
                Section {
                    row(memory, showsDate: false)
                } header: {
                    MonthHeader(title: Self.memoryTitle(memory), isDay: true)
                }
            }
        }
    }

    /// "1 year ago · Saturday, November 8, 2025".
    private static func memoryTitle(_ memory: EntrySummary) -> String {
        let date = memory.day?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? memory.date
        guard let years = memory.yearsAgo else { return date }
        return "\(years == 1 ? "1 year" : "\(years) years") ago · \(date)"
    }

    /// The Journal's row: tap to expand, again to open; swipe right for Actions, left to Open.
    private func row(_ entry: EntrySummary, showsDate: Bool) -> some View {
        TimelineEntryRow(entry: entry, isExpanded: expanded.contains(entry.id), showsDateWhenExpanded: showsDate, actions: actions,
                         onTap: {
                             if expanded.contains(entry.id) {
                                 path.append(EntryRoute(id: entry.id))
                             } else {
                                 withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) }
                             }
                         },
                         onOpen: { path.append(EntryRoute(id: entry.id)) })
            .entryPreview(entry) { path.append(EntryRoute(id: entry.id)) }
    }
}

private extension View {
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

    /// A band of the brand olive, so Today's sections read as separate once both have entries.
    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                appIcon(icon)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // The brand olive in both modes (dark mode's lighter accent is too pale behind white text).
        .background(Color(red: 0x5C / 255, green: 0x66 / 255, blue: 0x54 / 255), in: .rect(cornerRadius: 12))
    }
}
