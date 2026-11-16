import SwiftUI

/// Settings → Calendars: which of the phone's calendars the composer's "?" row lists events
/// from. All but subscribed ones to begin with.
struct CalendarSettingsView: View {
    @State private var access = DayCalendar.access
    @State private var calendars: [CalendarChoice] = []
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            // What the calendars are for, before the list of them.
            Section {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
            }
            switch access {
            case .notAsked:
                Section {
                    Button("Allow Calendar Access") {
                        Task {
                            _ = await DayCalendar.requestAccess()
                            load()
                        }
                    }
                }
            case .denied:
                Section {
                    Text("Allow access to your calendar to see events for the day you're writing about.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .allowed:
                if calendars.isEmpty {
                    Section {
                        Text("No calendars on this phone.").foregroundStyle(.secondary)
                    }
                }
                ForEach(accounts, id: \.self) { account in
                    Section {
                        ForEach(calendars.filter { $0.account == account }) { calendar in
                            Toggle(isOn: Binding(get: { calendar.isOn }, set: { on in
                                DayCalendar.setCalendar(calendar.id, on: on)
                                load()
                            })) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(calendar.color.map { Color(cgColor: $0) } ?? .secondary)
                                        .frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                    Text(calendar.title)
                                }
                            }
                        }
                    } header: {
                        if !account.isEmpty { Text(account) }
                    }
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        // Back from iOS's Settings, where access may have been allowed.
        .onChange(of: scenePhase) { _, phase in if phase == .active { load() } }
    }

    private var explanation: String {
        "When you're writing an entry, the ? button shows what was on your calendar that day, as a reminder of what happened. Choose which calendars it reads. Events stay on your phone and aren't sent to Dabble Me."
    }

    private var accounts: [String] {
        var seen = Set<String>()
        return calendars.map(\.account).filter { seen.insert($0).inserted }
    }

    private func load() {
        access = DayCalendar.access
        calendars = DayCalendar.calendars()
    }
}
