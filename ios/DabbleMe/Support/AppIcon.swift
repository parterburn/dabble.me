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
                .modifier(RoundButtonBacking(overPhoto: onDark))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// What's behind a round button: a light circle on a sheet, or, over a photo, the dark translucent
/// one the photo viewer's Save and Share have, which stands out on any picture.
struct RoundButtonBacking: ViewModifier {
    var overPhoto = false

    func body(content: Content) -> some View {
        if overPhoto {
            content
                .background(.black.opacity(0.45), in: .circle)
                .background(.ultraThinMaterial.opacity(0.6), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
        } else {
            content.background(Color.primary.opacity(0.08), in: .circle)
        }
    }
}

/// A row that opens a page of its own, with the Slab right arrow at its end in place of the
/// system's chevron (the link itself is laid over the row, unseen).
struct PaneLink<Destination: View, Label: View>: View {
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var label: () -> Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
            appIcon("slab-angle-right")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .background {
            NavigationLink(destination: destination) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        // One button to VoiceOver, named by the row (the link under it has no label of its own).
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// The Slab left arrow for a pushed page's Back, in place of the system chevron.
    func slabBackButton() -> some View { modifier(SlabBackButton()) }
}

private struct SlabBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        appIcon("slab-angle-left")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    .tint(.primary)
                    .accessibilityLabel("Back")
                }
            }
    }
}

/// A page without the system's Back button would lose the swipe back from the left edge: the
/// swipe is kept for any page that isn't the first.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// The top of a sheet: its title centered between a round button for the sheet's own action (when
/// it has one) at the left and the X at the right.
struct SheetHeader<Leading: View>: View {
    let title: String
    @ViewBuilder var leading: Leading

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 52) // clear of the buttons either side
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading
                Spacer()
                SheetCloseButton()
            }
        }
    }
}

extension SheetHeader where Leading == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A sheet header's round icon button (the X's twin).
struct SheetIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension Color {
    /// The app's red, for deleting (the link row's trash, Hold to Delete) and error messages:
    /// Tailwind's red-800, deeper than the system's fire-engine red; a brighter red-600 in Dark
    /// Mode, where red-800 would sink in.
    static let deleteRed = Color("DeleteRed")
}
