import SwiftUI

/// Settings → Accessibility: how entries read everywhere (the timeline, previews, an open entry
/// and the editor): their text size and a serif or sans-serif font.
struct AccessibilitySettingsView: View {
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    var body: some View {
        Form {
            Section {
                Picker("Entry Text Size", selection: $textSize) {
                    ForEach(ReadingTextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                Picker("Entry Font", selection: $fontStyle) {
                    ForEach(ReadingFontStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Entry Font")
            } footer: {
                Text("For your entries everywhere: the Journal, previews, an open entry and the editor. Pinching an open entry changes the size too. Text also follows your iPhone's text size.")
            }

            Section("Preview") {
                Text("How was your day? A little preview of how entries will read.")
                    .font(.system(size: bodySize * textSize.scale, design: fontStyle.design))
                    .lineSpacing(5 * textSize.scale)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}
