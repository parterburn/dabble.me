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
            // Pull to reset: collapses expanded entries and reloads today.
            .refreshable {
                withAnimation(.snappy(duration: 0.25)) { expanded = [] }
                await model.loadToday()
            }
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
            // On the prompt box's Paper card, so today stands apart from On This Day. Two rows (the
            // entry keeps its swipes), each drawing its half of the card.
            SectionTitle("Today's Entry", icon: "slab-calendar")
                .padding(.top, 6)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 14, leading: 32, bottom: 4, trailing: 32))
                .listRowBackground(TodayCard(edge: .top))
            row(entry.summary, showsDate: false)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 32, bottom: 16, trailing: 32))
                .listRowBackground(TodayCard(edge: .bottom))
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

/// Half of the Paper card behind Today's Entry (the same as the prompt box): the top half behind
/// its title, the bottom behind the entry, outlined everywhere but where they meet.
private struct TodayCard: View {
    enum Edge { case top, bottom }
    let edge: Edge

    var body: some View {
        let radius: CGFloat = 16
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: edge == .top ? radius : 0, bottomLeadingRadius: edge == .bottom ? radius : 0,
                                   bottomTrailingRadius: edge == .bottom ? radius : 0, topTrailingRadius: edge == .top ? radius : 0)
                .fill(Color("Paper"))
            CardOutline(edge: edge, radius: radius)
                .stroke(.quaternary, lineWidth: 1)
        }
        // Inset like the prompt box, which sits within the list's margins.
        .padding(.horizontal, 16)
        .padding(edge == .top ? .top : .bottom, 8)
    }

    /// The card's outline without the edge where the two halves meet.
    private struct CardOutline: Shape {
        let edge: Edge
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: 0.5, dy: 0.5)
            var path = Path()
            if edge == .top {
                path.move(to: CGPoint(x: r.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
                path.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
                path.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
                path.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: r.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
                path.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
                path.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
                path.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
                path.addLine(to: CGPoint(x: r.maxX, y: rect.minY))
            }
            return path
        }
    }
}
