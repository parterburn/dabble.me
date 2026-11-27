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

/// One of the app's icons set in a line of text, at the text's size and in its color: "the 💡
/// button", with the button's own icon. Read aloud as `name` (the button's label).
@MainActor
func inlineIcon(_ icon: String, named name: String, textStyle: UIFont.TextStyle = .subheadline) -> Text {
    let side = UIFont.preferredFont(forTextStyle: textStyle).pointSize * 1.05
    guard let image = appUIIcon(icon) else { return Text(name) }
    let sized = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    // (Sat a little under the baseline, so it's centred on the words' height.)
    return Text(Image(uiImage: sized).renderingMode(.template)).baselineOffset(-side * 0.14).accessibilityLabel(name)
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

/// A tap you can feel when a touch-and-hold takes (the "me" mark, an entry's date or pencil, the
/// composer's photos): the hold did something, where a tap would have done something else.
@MainActor
enum HoldHaptic {
    static func play() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

extension View {
    /// The app's filled button: the olive fill with white words, or in Dark Mode (where the
    /// olive is pale) with dark olive ones, which white is too faint against.
    func filledButtonStyle() -> some View {
        buttonStyle(.borderedProminent).foregroundStyle(Color("OnAccent"))
    }

    /// The Slab left arrow for a pushed page's Back, in place of the system chevron.
    /// `trail`: the pages behind this one, the nearest first. Touching and holding the arrow
    /// lists them, as the system's Back does, to go back more than one at once.
    /// `shown` false: no Back at all (the first page of the entry pane, which has nowhere to go).
    func slabBackButton(trail: [BackStep] = [], shown: Bool = true) -> some View { modifier(SlabBackButton(trail: trail, shown: shown)) }
}

/// A page to go back to: its name, and what takes you there.
struct BackStep: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let go: @MainActor () -> Void
}

extension EnvironmentValues {
    /// The pages behind an open entry (where it was opened from, then each entry opened from
    /// another's On This Day), the furthest first.
    @Entry var backTrail: [BackStep] = []
}

private struct SlabBackButton: ViewModifier {
    var trail: [BackStep] = []
    var shown = true
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if shown {
                    ToolbarItem(placement: .topBarLeading) {
                        if trail.count > 1 {
                            // A tap goes back one; held, it's a menu of everywhere to go back to.
                            Menu {
                                ForEach(trail) { step in
                                    Button(step.title) { step.go() }
                                }
                            } label: {
                                arrow
                            } primaryAction: {
                                dismiss()
                            }
                            .tint(.primary)
                            .accessibilityLabel("Back")
                        } else {
                            Button { dismiss() } label: { arrow }
                                .tint(.primary)
                                .accessibilityLabel("Back")
                        }
                    }
                }
            }
    }

    private var arrow: some View {
        appIcon("slab-angle-left")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(.primary)
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

/// The top of a sheet: its icon and title at the left (as a label, not a button) and the X at
/// the right, after a round button of the sheet's own when it has one.
struct SheetHeader<Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Label(title, icon: icon)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            accessory
            SheetCloseButton()
        }
    }
}

extension SheetHeader where Accessory == EmptyView {
    init(title: String, icon: String) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

extension Color {
    /// The app's red, for deleting (the link row's trash, Hold to Delete) and error messages:
    /// Tailwind's red-800, deeper than the system's fire-engine red; a brighter red-600 in Dark
    /// Mode, where red-800 would sink in.
    static let deleteRed = Color("DeleteRed")
}
