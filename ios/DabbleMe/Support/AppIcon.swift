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

/// The app's one X: the Slab close icon on a 44pt circle, at the top right of Random Memory,
/// Reflection and the photo viewer. Black on a light circle, or white on a translucent one over a
/// photo (`onDark`).
struct SheetCloseButton: View {
    var onDark = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            appIcon("slab-close")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(onDark ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(onDark ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

extension Color {
    /// The red for deleting (the link row's trash, Hold to Delete): Tailwind's red-800, deeper than
    /// the system's fire-engine red; a brighter red-600 in Dark Mode, where red-800 would sink in.
    static let deleteRed = Color("DeleteRed")
}
