import SwiftUI

/// A password field with an eye button that shows what's typed. Hidden by default, and hidden
/// again when the app leaves the foreground, so the app switcher snapshot never shows it.
/// Shown or hidden, the field keeps its text content type, so Passwords autofill still offers
/// the saved password. Keeps focus (and the keyboard) across the toggle.
///
/// Modifiers like `.submitLabel`, `.onSubmit` and `.disabled` go on this view as on a
/// SecureField. Focus is passed in, since `.focused` needs the field itself.
struct PasswordField<Value: Hashable>: View {
    @Environment(\.scenePhase) private var scenePhase
    let title: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    var focus: FocusState<Value>.Binding
    var equals: Value

    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(contentType)
            .focused(focus, equals: equals)

            Button(action: toggle) {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            // Borderless, so in a Form only the eye toggles, not a tap anywhere on the row.
            .buttonStyle(.borderless)
            .accessibilityLabel(revealed ? "Hide Password" : "Show Password")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealed = false }
        }
    }

    private func toggle() {
        // Swapping SecureField for TextField drops focus with the old field; put it back on
        // the new one so the keyboard stays up mid-typing.
        let wasFocused = focus.wrappedValue == equals
        revealed.toggle()
        if wasFocused {
            Task { @MainActor in focus.wrappedValue = equals }
        }
    }
}
