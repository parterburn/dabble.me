import SwiftUI
import UIKit

/// The app's icons: the Slab set (Font Awesome, as on dabble.me) where it has one, named "slab-…"
/// in the asset catalog; anything else is an SF Symbol.
func appIcon(_ name: String) -> Image {
    name.hasPrefix("slab-") ? Image(name) : Image(systemName: name)
}

func appUIIcon(_ name: String) -> UIImage? {
    name.hasPrefix("slab-") ? UIImage(named: name) : UIImage(systemName: name)
}

extension Label where Title == Text, Icon == Image {
    /// A label with a Slab icon ("slab-…") or an SF Symbol.
    init(_ title: String, icon: String) {
        self.init { Text(title) } icon: { appIcon(icon) }
    }
}

/// A sheet's X: the Slab close icon in black on a light circle (Random Memory, Reflection).
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: { Label("Close", icon: "slab-close") }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.primary)
            .foregroundStyle(.primary)
    }
}
