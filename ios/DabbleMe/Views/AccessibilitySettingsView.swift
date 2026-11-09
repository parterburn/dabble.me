import SwiftUI

/// Settings → Accessibility: the app's theme, and how entries read everywhere (the timeline,
/// previews, an open entry and the editor): a text size slider over a live preview, like
/// Twitter's, and a serif or sans-serif font.
struct AccessibilitySettingsView: View {
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    /// The slider's position: one stop per size.
    private var sizeStop: Binding<Double> {
        Binding(get: { Double(textSize.rawValue) },
                set: { textSize = ReadingTextSize(rawValue: Int($0.rounded())) ?? .standard })
    }

    var body: some View {
        Form {
            Section {
                preview
                HStack(spacing: 14) {
                    Text("Aa").font(.system(size: 15, design: fontStyle.design))
                    Slider(value: sizeStop, in: 0...Double(ReadingTextSize.allCases.count - 1), step: 1)
                        .accessibilityLabel("Entry Text Size")
                        .accessibilityValue(textSize.label)
                    Text("Aa").font(.system(size: 24, design: fontStyle.design))
                }
                .accessibilityElement(children: .contain)
                Picker("Entry Font", selection: $fontStyle) {
                    ForEach(ReadingFontStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Entry Font")
            } header: {
                Text("Entry Text")
            } footer: {
                Text("For your entries everywhere: the Journal, previews, an open entry and the editor. Pinching an open entry changes the size too. Text also follows your iPhone's text size.")
            }

            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Theme")
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your iPhone's Light or Dark Mode; Day and Night keep Dabble Me light or dark.")
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: textSize)
    }

    /// A made-up entry, set the way entries will read.
    private var preview: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text("SUN")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("8")
                    .font(.title2.weight(.semibold))
            }
            .frame(width: 42)
            Text("How was your day? A little preview of how entries will read: words, lists and #hashtags.")
                .font(.system(size: bodySize * textSize.scale, design: fontStyle.design))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .animation(.snappy(duration: 0.2), value: textSize)
        .accessibilityHidden(true)
    }
}
