#if os(watchOS)
import SwiftUI

/// An invisible view that owns the Digital Crown focus machinery.
///
/// **Why this exists:**
/// Placing `.focusable()` / `.digitalCrownRotation()` directly on a view that is
/// subscribed to a high-frequency `ObservableObject` (like `GameStateManager`) causes
/// WatchKit's internal `PUICCrownSequencer` to repeatedly lose and re-acquire its host
/// view reference as SwiftUI re-renders on every location / telemetry update. Each
/// re-render temporarily orphans the sequencer, producing the warning:
///   "Crown Sequencer was set up without a view property."
///
/// By isolating the crown machinery here — with **no** `@EnvironmentObject` and only
/// plain `Binding` and `Int` inputs — this view almost never re-renders, keeping the
/// sequencer stably attached to a single, long-lived SwiftUI view host.
public struct CrownInputView: View {
    /// Bound to the current zoom step index (0 = most zoomed out).
    var crownIndex: Binding<Double>
    /// Total number of discrete zoom steps.
    let scaleCount: Int
    /// Incremented by the parent to request focus re-capture (e.g. after a sheet dismisses).
    @Binding var focusTrigger: Int
    /// Called when the user taps; lets the parent also request focus.
    var onTap: () -> Void

    @FocusState private var isFocused: Bool
    @State private var lastTrigger: Int = 0

    public var body: some View {
        Color.clear
            .focusable()
            .focused($isFocused)
            .defaultFocus($isFocused, true)
            .digitalCrownRotation(
                crownIndex,
                from: 0.0,
                through: Double(scaleCount - 1),
                by: 1.0,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .digitalCrownAccessory(.automatic)
            .simultaneousGesture(
                TapGesture().onEnded { onTap() }
            )
            .onChange(of: focusTrigger) { _, newValue in
                guard newValue != lastTrigger else { return }
                lastTrigger = newValue
                isFocused = true
            }
            .onAppear {
                isFocused = true
            }
    }
}
#endif
