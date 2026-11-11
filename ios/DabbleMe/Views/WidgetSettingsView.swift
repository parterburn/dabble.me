import SwiftUI
import WidgetKit

/// Settings → Home Screen Widget: what the medium widget shows next to the year's entry count, with a live
/// preview from today's data (the same view the widget draws). The small widget is always just
/// the count, so the medium one is what changes.
struct WidgetSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var content = WidgetSnapshot.content
    /// Bumped once the shown entry's photo is ready, so the preview redraws with it.
    @State private var photoReady = 0

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Next to Your Entry Count", selection: $content) {
                    ForEach(WidgetContent.allCases) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(option.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Next to Your Entry Count")
            } footer: {
                footer
            }
        }
        .navigationTitle("Home Screen Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: content) { _, content in WidgetSync.setContent(content, model: model) }
        .task(id: content) {
            await WidgetSync.preparePreviewPhoto(for: content, model: model)
            photoReady += 1
        }
    }

    /// The medium widget, at its real size where it fits, on a home-screen-like background.
    private var preview: some View {
        let size = CGSize(width: 338, height: 158)
        let _ = photoReady // redraw once the photo is ready
        return TodayWidgetContent(entry: WidgetSync.previewEntry(for: content, model: model), family: .systemMedium)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Color.paper, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color("AccentColor").opacity(0.55), Color("AccentColor").opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 26)
            )
            .animation(.snappy(duration: 0.25), value: content)
            .allowsHitTesting(false) // a picture of the widget: its links are for the home screen
            .accessibilityElement(children: .combine) // read as one: what the widget would say
    }

    @ViewBuilder
    private var footer: some View {
        if content != .prompt, model.me?.isPro != true {
            Text("On This Day is part of Dabble Me PRO, so the widget shows a throwback or today's prompt instead.")
        } else {
            Text("Widgets can be seen without unlocking your phone. Add one by touching and holding your home screen.")
        }
    }
}
