import SwiftUI

/// Today: write (or add to) today's entry, and look back at this date in earlier years.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var composing = false
    @State private var showingProInfo = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
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
                        todaySection(today)
                        onThisDaySection(today)
                    } else if let error = model.timelineError {
                        ContentUnavailableView("Couldn't load today", systemImage: "wifi.exclamationmark", description: Text(error))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Today") // back-button label on entries opened from here
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
            .refreshable { await model.loadToday() }
            .sheet(isPresented: $composing) { ComposeView(mode: .new) }
            .sheet(isPresented: $showingProInfo) { ProInfoView(feature: .writing) }
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
                if model.me?.canWrite == true {
                    Button("Add to Today's Entry", systemImage: "plus") { composing = true }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let prompt = today.prompt {
                    Text("Today's prompt")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tint)
                    Text(prompt)
                        .font(.system(.title2, design: .serif))
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
                        Label("Write Today's Entry", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .background(Color("Paper"), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        }
    }

    // MARK: - On This Day

    @ViewBuilder
    private func onThisDaySection(_ today: TodaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("On This Day")
            if !today.onThisDayAvailable {
                Text("See what you wrote on this date in past years with Dabble Me PRO.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if today.onThisDay.isEmpty {
                Text("Nothing from this date in earlier years yet. Write today, and next year it'll be waiting for you here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(today.onThisDay) { memory in
                    NavigationLink(value: EntryRoute(id: memory.id)) {
                        MemoryCard(entry: memory, caption: caption(for: memory))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func caption(for memory: EntrySummary) -> String {
        let years = memory.yearsAgo ?? 0
        let ago = years == 1 ? "1 year ago" : "\(years) years ago"
        return "\(ago) · \(memory.day?.year ?? "")"
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
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
                    EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, size: .thumbnail)
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
