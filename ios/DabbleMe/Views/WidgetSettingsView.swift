import SwiftUI
import WidgetKit

/// Settings → Home Screen Widget: whether the widget shows entry previews, and what the medium
/// widget shows next to today's date (today's prompt or a Rewind), with a live
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
                Toggle("Show Entry Previews", isOn: previews)
            } footer: {
                Text("The start of an entry, and its photo, on the widget. Widgets can be seen without unlocking your phone.")
            }

            Section {
                Picker("Next to Today's Date", selection: source) {
                    ForEach(WidgetContent.Source.allCases) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(WidgetContent(source: option, showsPreviews: content.showsPreviews).summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Next to Today's Date")
            } footer: {
                footer
            }
        }
        .slabBackButton()
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

    private var source: Binding<WidgetContent.Source> {
        Binding { content.source } set: { content = WidgetContent(source: $0, showsPreviews: content.showsPreviews) }
    }

    private var previews: Binding<Bool> {
        Binding { content.showsPreviews } set: { content = WidgetContent(source: content.source, showsPreviews: $0) }
    }

    @ViewBuilder
    private var footer: some View {
        if content.source == .rewind, model.me?.isPro != true {
            Text("On This Day is part of Dabble Me PRO, so the widget looks back at another past entry instead. Add a widget by touching and holding your home screen.")
        } else {
            Text("Add a widget by touching and holding your home screen.")
        }
    }
}
