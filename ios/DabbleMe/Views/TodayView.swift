import SwiftUI

/// Today: write (or add to) today's entry, and look back at this date in earlier years.
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
                        .padding(.vertical, 8)
                        .plainRow()
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
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Today's Entry")
                NavigationLink(value: EntryRoute(id: entry.id)) {
                    MemoryCard(entry: entry.summary, caption: nil)
                }
                .buttonStyle(.plain)
                .entryPreview(entry.summary) { path.append(EntryRoute(id: entry.id)) }
                if model.me?.canWrite == true {
                    Button { composing = true } label: { Label("Add to Today's Entry", icon: "slab-plus") }
                        .buttonStyle(.bordered)
                }
            }
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
            // The same rows as the Journal: tap to expand, again to open; swipe for Reflect, Open, Actions.
            ForEach(today.onThisDay) { memory in
                TimelineEntryRow(entry: memory, showsYear: true, isExpanded: expanded.contains(memory.id), actions: actions,
                                 onTap: {
                                     if expanded.contains(memory.id) {
                                         path.append(EntryRoute(id: memory.id))
                                     } else {
                                         withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(memory.id) }
                                     }
                                 },
                                 onOpen: { path.append(EntryRoute(id: memory.id)) })
                    .entryPreview(memory) { path.append(EntryRoute(id: memory.id)) }
            }
        }
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

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                appIcon(icon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A larger, card-style entry preview for Today (memories read better with room to breathe).
private struct MemoryCard: View {
    let entry: EntrySummary
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let caption {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            HStack(alignment: .top, spacing: 12) {
                Text(entry.excerpt.isEmpty ? "📷 Photo" : entry.excerpt)
                    .font(.system(.body, design: .serif))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if entry.imageProcessing || entry.imageURL != nil {
                    EntryPhoto(url: entry.thumbnailURL(width: 168), isProcessing: entry.imageProcessing, size: .thumbnail)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
