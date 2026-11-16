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
            switch access {
            case .notAsked:
                Section {
                    Button("Allow Calendar Access") {
                        Task {
                            _ = await DayCalendar.requestAccess()
                            load()
                        }
                    }
                } footer: {
                    Text(explanation)
                }
            case .denied:
                Section {
                    Text("Allow access to your calendar to see events for the day you're writing about.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text(explanation)
                }
            case .allowed:
                if calendars.isEmpty {
                    Section {
                        Text("No calendars on this phone.").foregroundStyle(.secondary)
                    } footer: {
                        Text(explanation)
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
                    } footer: {
                        if account == accounts.last { Text(explanation) }
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
        "When you write, the ? button lists what was on these calendars that day, as a reminder. Events are read on your phone and aren't sent to Dabble Me."
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
