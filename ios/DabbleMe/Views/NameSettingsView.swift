import SwiftUI

/// Settings → Name: what Dabble Me calls you, saved to the account like the web settings. The
/// last name shows only for an account that has one (sign-up stopped asking for it). Saves on
/// Return or on leaving the page.
struct NameSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var firstName = ""
    @State private var lastName = ""
    /// Set when the page opens, so the last name stays while it's being cleared.
    @State private var showsLastName = false
    @State private var loaded = false
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case first, last }

    var body: some View {
        Form {
            Section {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(showsLastName ? .next : .done)
                    .focused($focused, equals: .first)
                    .onSubmit {
                        if showsLastName { focused = .last } else { save() }
                    }
                if showsLastName {
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .last)
                        .onSubmit(save)
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let me = model.me else { return }
            loaded = true
            firstName = me.firstName ?? ""
            lastName = me.lastName ?? ""
            showsLastName = me.lastName != nil
            // Straight to typing when there's no name yet.
            if me.firstName == nil { focused = .first }
        }
        .onDisappear(perform: save)
        .alert("Couldn't save your name", isPresented: .present($error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    /// Sends only what changed; nothing when nothing did.
    private func save() {
        guard loaded, let me = model.me else { return }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        var update = NameUpdate()
        if first != (me.firstName ?? "") { update.firstName = first }
        if showsLastName, last != (me.lastName ?? "") { update.lastName = last }
        guard update.firstName != nil || update.lastName != nil else { return }
        Task {
            do {
                try await model.saveName(update)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
